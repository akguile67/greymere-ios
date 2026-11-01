import Foundation
import Observation
import UIKit

// What the Ideation endpoints send and take (docs/ideation-exit-checklist.md; ADR 0.54.0).

struct IdeationConversation: Decodable, Sendable {
    struct Conv: Decodable, Sendable {
        let id: Int
        let synopsisDraft: String?
        let methodologyCodexEntryId: Int?
        let lastActiveAt: String?
    }
    let conversation: Conv
    let messages: [IdeationMessage]
    let bookTitle: String?
    let hasSavedSynopsis: Bool?
    let synopsisVersion: Int?
    let synopsisProposal: SynopsisProposal?
}

private struct RefreshResult: Decodable, Sendable { let synopsis: String?; let version: Int?; let costUsd: Double?; let discarded: Bool?; let note: String?; let synopsisProposal: SynopsisProposal? }
private struct ProposalBody: Encodable, Sendable { let proposal_id: Int; let base_version: Int? }
private struct AppliedResult: Decodable, Sendable { struct Syn: Decodable, Sendable { let text: String?; let version: Int? }; let synopsis: Syn? }
private struct LockResult: Decodable, Sendable { let already: Bool? }
private struct SaveResult: Decodable, Sendable { let ok: Bool?; let version: Int? }
private struct CodexName: Decodable, Sendable { let name: String }
/// `base_version` is the version the text was edited from; the server refuses a stale one with 409.
private struct DraftBody: Encodable, Sendable { let text: String; let base_version: Int? }

/// The desktop's refresh phrases. A message that is wholly one of them (with only filler words beside it) is a
/// command to refresh the synopsis; inside a longer sentence it is a request to Godric, who edits the synopsis himself.
enum RefreshPhrase {
    static let phrases = [
        "capture what we now know", "capture that", "capture this", "capture what we know",
        "refresh the synopsis", "update the synopsis", "rewrite the synopsis", "write that down", "write this down",
    ]
    private static let filler: Set<String> = ["please", "now", "again", "just", "ok", "okay", "thanks", "thank", "you", "go", "ahead", "and", "then", "so", "right"]

    static func isCommand(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return false }
        for phrase in phrases {
            let pattern = "(^|[\\s.,;!?])" + NSRegularExpression.escapedPattern(for: phrase) + "([\\s.,;!?]|$)"
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let r = Range(m.range, in: t) else { continue }
            var rest = t
            rest.replaceSubrange(r, with: " ")
            let words = rest.replacingOccurrences(of: "[.,;!?]", with: " ", options: .regularExpression)
                .split(separator: " ").map(String.init)
            if words.allSatisfy({ filler.contains($0) }) { return true }
        }
        return false
    }
}

/// The Ideation panel for one book at a time: its synopsis (read, edit, refresh, lock) and its Godric thread.
/// The server holds everything; this keeps what is on screen and an edit in progress.
@MainActor @Observable
final class IdeationModel {
    enum Work { case refreshing, saving, locking }
    struct Banner: Equatable { let text: String; var isError = false }

    let godric = GodricModel(thread: .ideation)

    var bookId: Int?
    var bookTitle = ""
    var synopsis = ""
    var hasSaved = false
    var methodology: String?
    var turns = 0
    var lastActive: String?
    var loading = false
    var loadError: String?

    var editing = false
    var editText = ""
    private var editBase = ""
    /// Set when the draft changed on the server while the author was editing: their text is held, nothing is overwritten.
    var theirs: String?
    private var theirsVersion: Int?
    /// The book's one working synopsis has a version; every write raises it.
    var synopsisVersion: Int?
    /// What Godric (or Refresh) has drafted and the author has not yet applied. Only Apply writes it.
    var proposal: SynopsisProposal?
    private var editVersion: Int?
    var working: Work?
    var banner: Banner?
    var changedByGodric = false
    var confirmLock = false
    /// Called after a lock, so Home shows the book's new state.
    var onLocked: (() async -> Void)?

    private var client: APIClient?
    private var loadedBook: Int?

    var hasSynopsis: Bool { !synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var wordCount: Int { synopsis.split(whereSeparator: \.isWhitespace).count }

    // MARK: opening

    /// Opens the book's Ideation conversation. This is a deliberate open: the server creates the conversation if there
    /// is none and puts the "Idea development" plan step back in progress, as on the desktop.
    func load(bookId: Int, title: String, client: APIClient) async {
        self.client = client
        godric.onRefreshCommand = { [weak self] in await self?.refresh() }
        godric.onContinued = { [weak self] in await self?.reload() }
        godric.onProposal = { [weak self] p in self?.proposal = p }
        godric.onNewConversation = { [weak self] in await self?.newConversation() }
        if loadedBook != bookId {
            if editing { cancelEdit() }                  // an edit never carries over to another book
            godric.resetIdeation()
            banner = nil; changedByGodric = false; theirs = nil
        }
        self.bookId = bookId; bookTitle = title
        loading = true; loadError = nil
        defer { loading = false }
        do {
            let r: IdeationConversation = try await client.get("/api/ideation/books/\(bookId)/conversation")
            await apply(r, client: client)
            loadedBook = bookId
        } catch {
            loadError = "Ideation couldn't be opened for this book."
        }
    }

    /// Re-reads the thread and synopsis (after a Continue).
    func reload() async {
        guard let bookId, let client else { return }
        if let r: IdeationConversation = try? await client.get("/api/ideation/books/\(bookId)/conversation") {
            await apply(r, client: client)
        }
    }

    private func apply(_ r: IdeationConversation, client: APIClient) async {
        if !editing { synopsis = r.conversation.synopsisDraft ?? ""; synopsisVersion = r.synopsisVersion }
        proposal = r.synopsisProposal
        hasSaved = r.hasSavedSynopsis ?? false
        turns = r.messages.filter { $0.kind == "chat" }.count
        lastActive = r.conversation.lastActiveAt.map { String($0.prefix(16)) }
        if let id = r.conversation.methodologyCodexEntryId {
            methodology = (try? await client.get("/api/codex/\(id)") as CodexName)?.name
        } else { methodology = nil }
        if let bookId { godric.seedIdeation(bookId: bookId, conversationId: r.conversation.id, methodology: methodology, messages: r.messages) }
    }

    /// Godric edited the synopsis during a turn: read it again, unless an edit is open (then it is left alone).
    func synopsisChangedByGodric() async {
        guard let bookId, let client, !editing else { return }
        if let r: IdeationConversation = try? await client.get("/api/ideation/books/\(bookId)/conversation") {
            synopsis = r.conversation.synopsisDraft ?? synopsis
            synopsisVersion = r.synopsisVersion
            changedByGodric = true
        }
    }

    // MARK: a new conversation

    /// Ends this book's Ideation conversation (it stays in History) and opens a blank one. The synopsis is the
    /// book's, not the conversation's, so nothing about it changes.
    func newConversation() async {
        guard let bookId, let client, !godric.busy, !editing else { return }
        godric.status = .thinking
        struct Ended: Decodable { let ok: Bool? }
        do {
            let _: Ended = try await client.post("/api/ideation/books/\(bookId)/end", body: EmptyBody())
            let r: IdeationConversation = try await client.get("/api/ideation/books/\(bookId)/conversation")
            godric.viewing = nil
            await apply(r, client: client)
        } catch {
            godric.status = .ready
            banner = Banner(text: "A new conversation couldn't be started: \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
        }
    }

    // MARK: editing by hand

    func beginEdit() {
        guard hasSynopsis, working == nil else { return }
        editText = synopsis; editBase = synopsis; editVersion = synopsisVersion
        banner = nil; editing = true
    }

    func cancelEdit() { editing = false; theirs = nil }

    /// Done editing. The save says which version of the synopsis it was edited from. If the book's synopsis has moved
    /// on (the laptop, or Godric), the server refuses with 409 and nothing is overwritten: the author chooses.
    func saveEdit() async {
        guard editing, bookId != nil, working == nil else { return }
        if editText == editBase { editing = false; return }
        await write(editText, base: editVersion)
    }

    private func write(_ text: String, base: Int?) async {
        guard let bookId, let client else { return }
        working = .saving
        defer { working = nil }
        do {
            let r: SaveResult = try await client.patch("/api/ideation/books/\(bookId)/synopsis-draft", body: DraftBody(text: text, base_version: base))
            synopsis = text; synopsisVersion = r.version ?? synopsisVersion
            editing = false; theirs = nil; changedByGodric = false
        } catch APIError.http(409, _) {
            // The refusal's body is cut short by the client, so the current text is read again, whole.
            if let r: IdeationConversation = try? await client.get("/api/ideation/books/\(bookId)/conversation") {
                theirs = r.conversation.synopsisDraft ?? ""
                theirsVersion = r.synopsisVersion
            } else {
                banner = Banner(text: "The synopsis changed, and it could not be read again. Your text is kept.", isError: true)
            }
        } catch {
            banner = Banner(text: "Save failed: \((error as? APIError)?.message ?? "could not reach the server"). Your text is kept.", isError: true)
        }
    }

    /// Overwrite deliberately: the save is sent again against the version just seen.
    func keepMine() async { await write(editText, base: theirsVersion) }

    func takeTheirs(copyMine: Bool = false) {
        if copyMine { UIPasteboard.general.string = editText }
        if let theirs { synopsis = theirs; synopsisVersion = theirsVersion ?? synopsisVersion }
        editing = false; self.theirs = nil
        changedByGodric = false
        if copyMine { banner = Banner(text: "Your text is on the clipboard.") }
    }

    // MARK: refresh and lock

    /// Refresh drafts a synopsis from the conversation so far. It is a draft: nothing changes until the author applies it.
    func refresh() async {
        guard let bookId, let client, working == nil, !editing else { return }
        working = .refreshing; banner = nil
        defer { working = nil }
        do {
            let r: RefreshResult = try await client.post("/api/ideation/books/\(bookId)/refresh-synopsis", body: EmptyBody())
            if r.discarded == true {
                banner = Banner(text: "Refresh dropped: the synopsis changed while it ran, so no draft was made. Refresh again if you still want it.")
            } else if let p = r.synopsisProposal {
                proposal = p
                banner = Banner(text: "Draft ready" + (r.costUsd.map { String(format: " · cost $%.2f", $0) } ?? "") + ". Review it below and press Apply.")
                godric.appendNote("Drafted a change from the conversation. Close this to review it. Apply and Discard are in the bar at the bottom; nothing changes until you press Apply.")
            } else {
                banner = Banner(text: r.note ?? "Nothing to draft from the conversation yet.")
            }
        } catch {
            banner = Banner(text: "Refresh failed: \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
        }
    }

    /// The one button that writes a draft. The server refuses it if the synopsis has moved on since the draft was made.
    func applyProposal() async {
        guard let proposal, let bookId, let client, working == nil else { return }
        working = .saving
        defer { working = nil }
        do {
            let r: AppliedResult = try await client.post("/api/ideation/books/\(bookId)/synopsis-proposal/apply",
                body: ProposalBody(proposal_id: proposal.id, base_version: proposal.baseVersion))
            if let t = r.synopsis?.text { synopsis = t }
            synopsisVersion = r.synopsis?.version ?? synopsisVersion
            self.proposal = nil
            changedByGodric = false
            banner = Banner(text: "Applied. The synopsis is now version \(synopsisVersion.map(String.init) ?? "?").")
        } catch APIError.http(409, _) {
            await reload()
            banner = Banner(text: "The synopsis changed since this was drafted, so it was not applied. Ask Godric to draft it again.", isError: true)
        } catch {
            banner = Banner(text: "Apply failed: \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
        }
    }

    func discardProposal() async {
        guard let proposal, let bookId, let client, working == nil else { return }
        do {
            struct Discarded: Decodable { let ok: Bool? }
            let _: Discarded = try await client.post("/api/ideation/books/\(bookId)/synopsis-proposal/discard", body: ProposalBody(proposal_id: proposal.id, base_version: nil))
            self.proposal = nil
            banner = Banner(text: "Draft discarded. The synopsis is unchanged.")
        } catch {
            banner = Banner(text: "Discard failed: \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
        }
    }

    /// Lock asks first only when the book has no saved synopsis, as the desktop does.
    func requestLock() async {
        guard hasSynopsis, working == nil, !editing else { return }
        if hasSaved { await lock() } else { confirmLock = true }
    }

    func lock() async {
        guard let bookId, let client else { return }
        working = .locking; banner = nil
        defer { working = nil }
        do {
            let r: LockResult = try await client.post("/api/ideation/books/\(bookId)/lock-synopsis", body: EmptyBody())
            hasSaved = true
            banner = Banner(text: r.already == true
                ? "Synopsis locked · already the working copy, nothing further to change"
                : "Synopsis locked · Godric reads this version · the book is in the Codex update")
            await onLocked?()
        } catch {
            banner = Banner(text: "Lock failed: \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
        }
    }
}
