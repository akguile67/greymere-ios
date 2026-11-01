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
    struct Ref: Decodable, Sendable { let id: Int }
    let conversation: Ref?
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
    let bookId: Int?
    var id: String { key }
}

/// What Continue answers: `reopened` (the conversation is the panel's active thread again) or `carried` (its
/// transcript was put into this panel's thread).
struct HistoryContinue: Decodable, Sendable {
    let mode: String?
    let newConversation: Bool?
}

/// The Ideation endpoints' own shapes (`GET /api/ideation/books/:id/conversation`, `POST …/messages`).
struct IdeationMessage: Decodable, Sendable {
    let role: String
    let kind: String
    let textOnly: String?
    let createdAt: String?
}

struct IdeationReply: Decodable, Sendable {
    let text: String
    let synopsisUpdated: Bool?
    /// Godric drafted a change to the synopsis this turn. It is only a draft: the author applies it.
    let synopsisProposed: Bool?
    let synopsisProposal: SynopsisProposal?
}

/// A change to the book's synopsis that Godric (or Refresh) has drafted and the author has not yet applied.
struct SynopsisProposal: Decodable, Sendable, Identifiable, Equatable {
    struct Change: Decodable, Sendable, Equatable, Identifiable {
        let before: String
        let after: String
        var id: String { "\(before.hashValue)-\(after.hashValue)" }
    }
    let id: Int
    let source: String?
    let baseVersion: Int
    let stale: Bool?
    let changes: [Change]
    let proposedText: String?
}

private struct IdeationSend: Encodable { let text: String; let source_pane = "right_panel" }

/// The server reads these keys as written (camelCase). `quickOpen` asks for the fixed greeting instead of a model-written brief.
private struct ConversationRequest: Encodable { let context: String; let bookId: Int?; var quickOpen = true }
private struct ChatRequest: Encodable { let context: String; let message: String; let bookId: Int?; var quickOpen = true }
private struct ContinueRequest: Encodable { let key: String; let context: String; let bookId: Int?; let into: String? }
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
    /// Which panel's thread this is. Home chat is `/api/godric/*`; Ideation is the book's own thread.
    enum Thread { case home, ideation }

    let thread: Thread
    init(thread: Thread = .home) { self.thread = thread }

    /// The panel context the server keys the thread by.
    var contextName: String { thread == .home ? "home" : "ideation" }

    var messages: [ChatMessage] = []
    var status: GodricStatus = .ready
    var busy = false
    var loaded = false
    var temporal: Temporal?
    var history: [HistoryEntry] = []
    var viewing: HistoryEntry?
    /// The History key of the thread now on screen (`g-N` or `i-N`), so History can mark it and not offer to
    /// continue a conversation that is already the one in use.
    var activeKey: String?
    /// Set when Continue is pressed on a conversation from another panel or book: the author chooses between
    /// starting a new conversation from it and adding it to the current one.
    var askContinueChoice = false
    /// Ideation only: start a blank conversation for the book (the old one stays in History).
    var onNewConversation: (() async -> Void)?
    /// Continue's failure, in the server's words; the past conversation stays on screen.
    var continueError: String?
    /// Counts replies in which Godric edited the synopsis, so the Ideation screen knows to repaint.
    var synopsisTick = 0
    /// Ideation only: Godric drafted a synopsis change in this turn.
    var onProposal: ((SynopsisProposal?) -> Void)?
    /// Ideation only: reload the book's thread and synopsis after a Continue.
    var onContinued: (() async -> Void)?

    private var activeMessages: [ChatMessage] = []
    private var focusedBookId: Int?
    private var generation = 0

    // MARK: lifecycle

    /// Opens (or restores) this panel's thread. A book in focus is sent, and noted when it changes.
    func open(client: APIClient, book: (id: Int, title: String)? = nil) async {
        guard thread == .home else { return }   // Ideation's thread is loaded with its synopsis, by IdeationModel
        if loaded, viewing == nil {
            await noteBook(book, client: client)
            return
        }
        status = .thinking
        generation += 1
        let mine = generation
        do {
            let r: ConversationResponse = try await client.post("/api/godric/conversation",
                body: ConversationRequest(context: contextName, bookId: book?.id))
            guard mine == generation else { return }
            apply(r)
            focusedBookId = book?.id
            loaded = true
            status = .ready
            if let book {
                _ = try? await client.post("/api/godric/book-switch",
                    body: BookSwitchRequest(screen: contextName, bookId: book.id, bookTitle: book.title), as: Ignored.self)
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
            body: BookSwitchRequest(screen: contextName, bookId: book.id, bookTitle: book.title), as: Ignored.self)
    }

    private func apply(_ r: ConversationResponse) {
        activeKey = r.conversation.map { "g-\($0.id)" }
        activeMessages = r.messages.map(Self.map)
        messages = activeMessages
        temporal = r.temporal
        viewing = nil
    }

    func newChat(client: APIClient) async {
        guard !busy else { return }
        if thread == .ideation { await onNewConversation?(); return }
        status = .thinking
        do {
            let r: ConversationResponse = try await client.post("/api/godric/conversation/new",
                body: ConversationRequest(context: contextName, bookId: focusedBookId))
            apply(r)
            status = .ready
        } catch { fail(error, opening: false) }
    }

    // MARK: ideation thread

    /// Puts the book's Ideation thread on screen: the chat and opening turns, under a note saying what it runs against.
    func seedIdeation(bookId: Int, conversationId: Int, methodology: String?, messages server: [IdeationMessage]) {
        focusedBookId = bookId
        activeKey = "i-\(conversationId)"
        let opener = ChatMessage(role: .note,
            text: "Ideation conversation — \(methodology.map { "against \($0)" } ?? "no methodology bound")", time: nil)
        let turns = server.filter { $0.kind == "chat" || $0.kind == "opening" }.map {
            Self.shaped(role: $0.role == "user" ? .user : .godric, text: $0.textOnly ?? "", time: Self.parse($0.createdAt))
        }
        activeMessages = [opener] + turns
        if viewing == nil { messages = activeMessages }
        status = .ready
        loaded = true
        status = .ready
    }

    func appendNote(_ text: String) {
        messages.append(ChatMessage(role: .note, text: text, time: nil))
        activeMessages = messages
    }

    func resetIdeation() {
        activeMessages = []; messages = []; viewing = nil; loaded = false
    }

    // MARK: sending

    func send(_ raw: String, client: APIClient) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, viewing == nil else { return }
        busy = true
        status = .thinking
        messages.append(ChatMessage(role: .user, text: text, time: Date()))
        if thread == .ideation, let bookId = focusedBookId {
            do {
                let r: IdeationReply = try await client.post("/api/ideation/books/\(bookId)/messages", body: IdeationSend(text: text))
                messages.append(ChatMessage(role: .godric, text: r.text, time: Date()))
                if r.synopsisUpdated == true { synopsisTick += 1 }
                if r.synopsisProposed == true, let p = r.synopsisProposal {
                    onProposal?(p)
                    messages.append(ChatMessage(role: .note, text: "Godric drafted a change to the synopsis. Close this to review it. Apply and Discard are in the bar at the bottom; nothing changes until you press Apply.", time: nil))
                }
                status = .ready
            } catch {
                fail(error, opening: false)
            }
            activeMessages = messages
            busy = false
            return
        }
        do {
            let r: ChatReply = try await client.post("/api/godric/chat",
                body: ChatRequest(context: contextName, message: text, bookId: focusedBookId))
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
        // The thread already in use is not "a past conversation": History just takes the author back to it.
        if entry.key == activeKey { leaveHistory(); return }
        guard let past: Past = try? await client.get("/api/godric/conversation/\(entry.key)") else { return }
        viewing = entry
        continueError = nil
        messages = past.messages.map(Self.map)
    }

    /// Closing Godric leaves any past conversation being read, so he opens on the live thread next time.
    func leaveHistory() { if viewing != nil { backToActive() } }

    func backToActive() {
        viewing = nil
        continueError = nil
        messages = activeMessages
        status = .ready
    }

    /// A conversation from this same panel (for Ideation, this same book) reopens as itself. One from elsewhere
    /// would have to be carried into a thread, so the author is asked first.
    var viewingIsFromHere: Bool {
        guard let entry = viewing else { return true }
        switch thread {
        case .ideation: return entry.key.hasPrefix("i-") && entry.bookId == focusedBookId
        case .home: return entry.key.hasPrefix("g-") && (entry.panel ?? "home") == "home"
        }
    }

    func pressContinue(client: APIClient) async {
        if viewingIsFromHere { await continueViewing(client: client, intoNew: false) } else { askContinueChoice = true }
    }

    /// Unlocks a past conversation so the talk can go on. From here it reopens as itself and the conversation the
    /// author was in is parked in History. From elsewhere it starts a new conversation with it carried in
    /// (`intoNew`), or is added to the current one. A refusal is shown in the server's words with the past
    /// conversation left on screen.
    func continueViewing(client: APIClient, intoNew: Bool) async {
        guard let entry = viewing, !busy else { return }
        continueError = nil
        let result: HistoryContinue
        do {
            result = try await client.post("/api/godric/conversation/continue",
                body: ContinueRequest(key: entry.key, context: contextName, bookId: focusedBookId, into: intoNew ? "new" : nil))
        } catch {
            continueError = (error as? APIError)?.message ?? "Could not continue this conversation."
            return
        }
        viewing = nil
        if thread == .ideation { await onContinued?() } else { loaded = false; await open(client: client) }
        let title = entry.title.map { " “\($0)”" } ?? ""
        let note = result.newConversation == true ? "Started a new conversation from:\(title)"
            : result.mode == "carried" ? "Brought into this chat:\(title)" : "Reopened:\(title)"
        messages.append(ChatMessage(role: .note, text: note, time: nil))
        activeMessages = messages
    }

    // MARK: helpers

    private static func map(_ m: ServerMessage) -> ChatMessage {
        let role: ChatMessage.Role = (m.kind == "context_shift" || m.kind == "book_switch") ? .note
            : (m.role == "user" ? .user : .godric)
        return shaped(role: role, text: m.content, time: parse(m.createdAt))
    }

    /// A conversation carried in from elsewhere is stored as one long turn holding its whole transcript. On a phone it
    /// reads as a single line saying what was brought in, not a wall of text.
    private static func shaped(role: ChatMessage.Role, text: String, time: Date?) -> ChatMessage {
        guard text.hasPrefix("[Carried in from an earlier conversation") else { return ChatMessage(role: role, text: text, time: time) }
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text
        let line = first.trimmingCharacters(in: CharacterSet(charactersIn: "[ .")).replacingOccurrences(of: "Carried in from", with: "Brought in from")
        return ChatMessage(role: .note, text: line, time: time)
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
