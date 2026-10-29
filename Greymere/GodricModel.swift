import Foundation
import Observation

// What the Godric endpoints send, as the desktop panel reads it (docs/godric-chat-exit-checklist.md).

struct ServerMessage: Decodable, Sendable {
    let role: String
    let kind: String
    let content: String
    let createdAt: String?
}

struct Temporal: Decodable, Sendable {
    let isWorkingDay: Bool?
    let nextWorkingLabel: String?
}

struct ConversationResponse: Decodable, Sendable {
    let messages: [ServerMessage]
    let temporal: Temporal?
}

/// Present when the server returned the field with a value; the app only needs to know a draft exists.
struct Present: Decodable, Sendable { init(from decoder: Decoder) throws {} }

struct ChatReply: Decodable, Sendable {
    let text: String
    let pendingCodexChange: Present?
    let pendingContentDraft: Present?
    let pendingCoverBriefChange: Present?
    let pendingCoverBriefExport: Present?
    var hasProposal: Bool {
        pendingCodexChange != nil || pendingContentDraft != nil
            || pendingCoverBriefChange != nil || pendingCoverBriefExport != nil
    }
}

struct HistoryEntry: Decodable, Sendable, Identifiable {
    let key: String
    let panel: String?
    let title: String?
    let summary: String?
    let lastActiveAt: String?
    var id: String { key }
}

struct HistoryContinue: Decodable, Sendable {
    let messages: [ServerMessage]?
}

private struct ConversationRequest: Encodable { let context: String; let bookId: Int? }
private struct ChatRequest: Encodable { let context: String; let message: String; let bookId: Int? }
private struct ContinueRequest: Encodable { let key: String; let context: String; let bookId: Int? }
private struct BookSwitchRequest: Encodable { let screen: String; let bookId: Int; let bookTitle: String }
private struct Ignored: Decodable, Sendable {}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, godric, note, error }
    let id = UUID()
    let role: Role
    let text: String
    let time: Date?
    var hasProposal = false
}

enum GodricStatus { case ready, thinking, offline }

/// Godric chat. The server holds the conversation, the context and the memory; this keeps only what is on screen.
/// The reply arrives whole, as on the desktop: there is no streaming (checklist, finding 1).
@MainActor @Observable
final class GodricModel {
    /// The only panel context the app has in 0.3.0.
    static let context = "home"

    var messages: [ChatMessage] = []
    var status: GodricStatus = .ready
    var busy = false
    var loaded = false
    var temporal: Temporal?
    var history: [HistoryEntry] = []
    var viewing: HistoryEntry?
    var showQuickActions = false

    private var activeMessages: [ChatMessage] = []
    private var focusedBookId: Int?
    private var generation = 0

    var quickActions: [String] {
        guard showQuickActions, viewing == nil else { return [] }
        if temporal?.isWorkingDay == false {
            let label = (temporal?.nextWorkingLabel ?? "next working day").split(separator: ",").first.map(String.init) ?? "next working day"
            return ["Quick portfolio snapshot", "Anything I should know before \(label)?", "Talk through where The House is at"]
        }
        return ["What should I work on today?", "Show me schedule pressure across the portfolio", "Which book is most at risk?"]
    }

    // MARK: lifecycle

    /// Opens (or restores) this panel's thread. A book in focus is sent, and noted when it changes.
    func open(client: APIClient, book: (id: Int, title: String)? = nil) async {
        if loaded, viewing == nil {
            await noteBook(book, client: client)
            return
        }
        status = .thinking
        generation += 1
        let mine = generation
        do {
            let r: ConversationResponse = try await client.post("/api/godric/conversation",
                body: ConversationRequest(context: Self.context, bookId: book?.id))
            guard mine == generation else { return }
            apply(r)
            focusedBookId = book?.id
            loaded = true
            status = .ready
            if let book {
                _ = try? await client.post("/api/godric/book-switch",
                    body: BookSwitchRequest(screen: Self.context, bookId: book.id, bookTitle: book.title), as: Ignored.self)
            }
        } catch {
            guard mine == generation else { return }
            fail(error, opening: true)
        }
    }

    private func noteBook(_ book: (id: Int, title: String)?, client: APIClient) async {
        guard let book, book.id != focusedBookId else { return }
        focusedBookId = book.id
        _ = try? await client.post("/api/godric/book-switch",
            body: BookSwitchRequest(screen: Self.context, bookId: book.id, bookTitle: book.title), as: Ignored.self)
    }

    private func apply(_ r: ConversationResponse) {
        activeMessages = r.messages.map(Self.map)
        messages = activeMessages
        temporal = r.temporal
        viewing = nil
        showQuickActions = !r.messages.contains { $0.role == "user" }
    }

    func newChat(client: APIClient) async {
        guard !busy else { return }
        status = .thinking
        do {
            let r: ConversationResponse = try await client.post("/api/godric/conversation/new",
                body: ConversationRequest(context: Self.context, bookId: focusedBookId))
            apply(r)
            status = .ready
        } catch { fail(error, opening: false) }
    }

    // MARK: sending

    func send(_ raw: String, client: APIClient) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, viewing == nil else { return }
        busy = true
        showQuickActions = false
        status = .thinking
        messages.append(ChatMessage(role: .user, text: text, time: Date()))
        do {
            let r: ChatReply = try await client.post("/api/godric/chat",
                body: ChatRequest(context: Self.context, message: text, bookId: focusedBookId))
            messages.append(ChatMessage(role: .godric, text: r.text, time: Date(), hasProposal: r.hasProposal))
            status = .ready
        } catch {
            fail(error, opening: false)
        }
        activeMessages = messages
        busy = false
    }

    private func fail(_ error: Error, opening: Bool) {
        let text: String
        switch error {
        case APIError.http(let code, let body):
            text = opening ? "Godric is offline — \(code). \(body)" : "Godric error \(code) — \(body)"
        default:
            text = "Could not reach Godric — check that Tailscale is on."
        }
        messages.append(ChatMessage(role: .error, text: text, time: Date()))
        status = .offline
    }

    // MARK: history

    func loadHistory(client: APIClient) async {
        if let list: [HistoryEntry] = try? await client.get("/api/godric/conversations?limit=40") { history = list }
    }

    func view(_ entry: HistoryEntry, client: APIClient) async {
        struct Past: Decodable { let messages: [ServerMessage] }
        guard let past: Past = try? await client.get("/api/godric/conversation/\(entry.key)") else { return }
        viewing = entry
        messages = past.messages.map(Self.map)
    }

    func backToActive() {
        viewing = nil
        messages = activeMessages
        status = .ready
    }

    func continueViewing(client: APIClient) async {
        guard let entry = viewing else { return }
        _ = try? await client.post("/api/godric/conversation/continue",
            body: ContinueRequest(key: entry.key, context: Self.context, bookId: focusedBookId), as: Ignored.self)
        loaded = false
        viewing = nil
        await open(client: client)
    }

    // MARK: helpers

    private static func map(_ m: ServerMessage) -> ChatMessage {
        let role: ChatMessage.Role = (m.kind == "context_shift" || m.kind == "book_switch") ? .note
            : (m.role == "user" ? .user : .godric)
        return ChatMessage(role: role, text: m.content, time: parse(m.createdAt))
    }

    /// The server writes UTC as "YYYY-MM-DD HH:MM:SS" (or ISO).
    private static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
