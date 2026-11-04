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

/// A proposal id as the server sends it (text or a number), sent back the way it came.
struct FlexID: Codable, Hashable, Sendable {
    let text: String
    let isNumber: Bool
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { text = String(i); isNumber = true } else { text = try c.decode(String.self); isNumber = false }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if isNumber, let i = Int(text) { try c.encode(i) } else { try c.encode(text) }
    }
}

/// A change to a Codex entry that Godric drafted in chat. Nothing is written until the author presses Apply.
struct CodexChangeCard: Decodable, Sendable, Equatable, Identifiable {
    struct Entry: Decodable, Sendable, Equatable { let id: Int?; let name: String; let type: String }
    let proposalId: FlexID
    let conversationId: Int
    let kind: String
    let entry: Entry
    let currentBody: String
    let proposedBody: String
    let newAliases: [String]?
    let reason: String?
    var id: String { proposalId.text }
    static func == (a: CodexChangeCard, b: CodexChangeCard) -> Bool { a.proposalId == b.proposalId && a.conversationId == b.conversationId }
}

/// What the open Codex screen tells Godric (the server reads the open entry from the database).
struct CodexPanelContext: Encodable, Sendable {
    let filter: String
    let entryId: Int?
    private enum CodingKeys: String, CodingKey { case filter, entryId = "entry_id" }
}
private struct CodexProposalCall: Encodable { let conversationId: Int; let proposalId: FlexID
    private enum CodingKeys: String, CodingKey { case conversationId = "conversation_id", proposalId = "proposal_id" } }

struct ChatReply: Decodable, Sendable {
    let text: String
    let pendingCodexChange: CodexChangeCard?
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
    /// Set when the draft removes more than a tenth of the synopsis.
    struct Shrinks: Decodable, Sendable, Equatable { let wordsRemoved: Int; let percent: Int }
    let id: Int
    let source: String?
    let baseVersion: Int
    let stale: Bool?
    let shrinks: Shrinks?
    let changes: [Change]
    let proposedText: String?
}

private struct CreationSend: Encodable { let text: String }
private struct IdeationSend: Encodable { let text: String; let source_pane = "right_panel" }

/// The server reads these keys as written (camelCase). `quickOpen` asks for the fixed greeting instead of a model-written brief.
private struct ConversationRequest: Encodable { let context: String; let bookId: Int?; var quickOpen = true }
private struct ChatRequest: Encodable { let context: String; let message: String; let bookId: Int?; var quickOpen = true; var codexPanelContext: CodexPanelContext? }
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
    var codexChange: CodexChangeCard?
    /// Set once the author has dealt with the drafted change: "Applied" or "Discarded".
    var outcome: String?
}

enum GodricStatus { case ready, thinking, offline }

/// Godric chat. The server holds the conversation, the context and the memory; this keeps only what is on screen.
/// The reply arrives whole, as on the desktop: there is no streaming (checklist, finding 1).
@MainActor @Observable
final class GodricModel {
    /// Which panel's thread this is. Home chat is `/api/godric/*`; Ideation is the book's own thread; Creation is the open chapter's.
    enum Thread { case home, ideation, creation, codex }

    let thread: Thread
    init(thread: Thread = .home) { self.thread = thread }

    /// The panel context the server keys the thread by.
    var contextName: String { switch thread { case .home: "home"; case .ideation: "ideation"; case .creation: "creation"; case .codex: "codex" } }
    /// Codex only: what is open now, read each time a message is sent.
    var codexContext: (() -> CodexPanelContext)?
    /// Codex only: a drafted change was applied, so the Codex should look again.
    var onCodexApplied: (() async -> Void)?

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
    /// Creation only: Godric drafted a change to a beat in this turn. It is only a draft: the author applies it.
    var onBeatProposal: ((BeatProposalCard?) -> Void)?
    /// Ideation only: reload the book's thread and synopsis after a Continue.
    var onContinued: (() async -> Void)?

    private var activeMessages: [ChatMessage] = []
    private var focusedBookId: Int?
    private var focusedChapterId: Int?
    private var generation = 0

    // MARK: lifecycle

    /// Opens (or restores) this panel's thread. A book in focus is sent, and noted when it changes.
    func open(client: APIClient, book: (id: Int, title: String)? = nil) async {
        guard thread == .home || thread == .codex else { return }   // Ideation's thread is loaded with its synopsis, by IdeationModel
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
        if thread == .creation { return }
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

    // MARK: creation thread

    /// Puts the open chapter's thread on screen. The server keeps the one thread per chapter; there is no History for it.
    func seedCreation(bookId: Int, chapterId: Int, title: String?, messages server: [CreationMessage]) {
        focusedBookId = bookId; focusedChapterId = chapterId
        activeKey = "c-\(chapterId)"
        let opener = ChatMessage(role: .note, text: "Chapter conversation" + (title.map { " — \($0)" } ?? ""), time: nil)
        let turns = server.filter { $0.kind == "chat" || $0.kind == "opening" }.map {
            ChatMessage(role: $0.role == "user" ? .user : .godric, text: $0.text, time: Self.parse($0.createdAt))
        }
        activeMessages = [opener] + turns
        messages = activeMessages
        status = .ready
        loaded = true
    }

    func resetCreation() {
        activeMessages = []; messages = []; viewing = nil; loaded = false; focusedChapterId = nil; status = .ready
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
        if thread == .creation, let chapterId = focusedChapterId {
            do {
                // A reply is one JSON response and can take about a minute; APIClient's POST waits up to ten.
                let r: CreationReply = try await client.post("/api/creation/chapters/\(chapterId)/godric", body: CreationSend(text: text))
                messages.append(ChatMessage(role: .godric, text: r.text, time: Date()))
                if let p = r.pendingBeatChange {
                    onBeatProposal?(p)
                    messages.append(ChatMessage(role: .note, text: "Godric drafted a change to a beat. Close this to review it. Apply and Discard are on the chapter; nothing changes until you press Apply.", time: nil))
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
                body: ChatRequest(context: contextName, message: text, bookId: focusedBookId, codexPanelContext: thread == .codex ? codexContext?() : nil))
            messages.append(ChatMessage(role: .godric, text: r.text, time: Date(), hasProposal: r.hasProposal && r.pendingCodexChange == nil, codexChange: r.pendingCodexChange))
            status = .ready
        } catch {
            fail(error, opening: false)
        }
        activeMessages = messages
        busy = false
    }

    /// Applies or discards a Codex change Godric drafted. Apply is refused by the server if the entry moved on.
    func resolveCodexChange(_ card: CodexChangeCard, apply: Bool, client: APIClient) async {
        guard let i = messages.firstIndex(where: { $0.codexChange?.id == card.id }) else { return }
        do {
            let _: Present = try await client.post(apply ? "/api/godric/codex-proposal/apply" : "/api/godric/codex-proposal/discard",
                                                   body: CodexProposalCall(conversationId: card.conversationId, proposalId: card.proposalId))
            messages[i].outcome = apply ? "Applied" : "Discarded"
            activeMessages = messages
            if apply { await onCodexApplied?() }
        } catch let e as APIError { messages.append(ChatMessage(role: .error, text: e.message, time: nil)) }
        catch { messages.append(ChatMessage(role: .error, text: "That did not work.", time: nil)) }
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
        case .creation: return true
        case .home: return entry.key.hasPrefix("g-") && (entry.panel ?? "home") == "home"
        case .codex: return entry.key.hasPrefix("g-") && entry.panel == "codex"
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
