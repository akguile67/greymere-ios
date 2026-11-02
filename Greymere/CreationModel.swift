import Foundation
import Observation

// What the Creation endpoints send and take (ADR 0.55.0; docs/adrs/adr-0.55.0-step0-audit-note.md in the server repo).

struct CreationBookSummary: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
}

private struct CreationBooksResponse: Decodable, Sendable { let books: [CreationBookSummary] }

struct CreationChapterCard: Decodable, Sendable, Identifiable {
    struct Warning: Decodable, Sendable { let name: String }
    let id: Int
    let number: Int?
    let title: String?
    let creationStatus: String?
    let briefed: Bool?
    let canDraft: Bool?
    let beatCount: Int?
    let wordCount: Int?
    let codexWarning: [Warning]?
}

struct CreationAct: Decodable, Sendable, Identifiable {
    let id: Int
    let number: Int?
    let title: String?
    let chapters: [CreationChapterCard]
    let briefedCount: Int?
    let draftOneCount: Int?
}

struct CreationBookDoc: Decodable, Sendable {
    struct Head: Decodable, Sendable { let id: Int; let title: String; let number: Int? }
    let book: Head
    let acts: [CreationAct]
}

/// A codex reference on a beat. The server sends objects; a bare string is tolerated.
struct BeatRef: Decodable, Sendable, Identifiable, Hashable {
    let name: String
    let codexId: Int?
    let type: String?
    let exists: Bool?
    let needsDevelopment: Bool?
    var id: String { name.lowercased() }

    init(name: String, codexId: Int? = nil, type: String? = nil) {
        self.name = name; self.codexId = codexId; self.type = type; exists = nil; needsDevelopment = nil
    }

    private enum Keys: String, CodingKey { case name, codexId, type, exists, needsDevelopment }
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            name = s; codexId = nil; type = nil; exists = nil; needsDevelopment = nil
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        codexId = try c.decodeIfPresent(Int.self, forKey: .codexId)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        exists = try c.decodeIfPresent(Bool.self, forKey: .exists)
        needsDevelopment = try c.decodeIfPresent(Bool.self, forKey: .needsDevelopment)
    }
}

struct CreationBeat: Decodable, Sendable, Identifiable, Equatable {
    struct Continuity: Decodable, Sendable, Equatable { let note: String?; let acceptedAt: String? }
    let id: Int
    let sceneId: Int
    let number: Int?
    let whatHappens: String
    let targetWords: Int?
    let refs: [BeatRef]?
    let proposedRefs: [BeatRef]?
    let dismissedRefs: [String]?
    /// The paragraph of the manuscript this beat goes in front of; nil is the end of the chapter.
    let position: Int?
    /// A generated draft waiting for Accept. Read-only in 0.6.0 Sprint 2.
    let proposal: String?
    let continuity: Continuity?

    /// Godric's confirmed list, or his proposal when nothing is confirmed (as the desktop shows it).
    var shownRefs: [BeatRef] {
        if let refs, !refs.isEmpty { return refs }
        return proposedRefs ?? []
    }
    var dismissed: [String] { dismissedRefs ?? [] }
    var activeRefs: [BeatRef] {
        let skip = Set(dismissed.map { $0.lowercased() })
        return shownRefs.filter { !skip.contains($0.name.lowercased()) }
    }
    var openContinuity: Continuity? {
        guard let c = continuity, let note = c.note, !note.isEmpty, c.acceptedAt == nil else { return nil }
        return c
    }
    var acceptedContinuity: Bool {
        guard let c = continuity, let note = c.note, !note.isEmpty else { return false }
        return c.acceptedAt != nil
    }

    static func == (a: CreationBeat, b: CreationBeat) -> Bool { a.id == b.id && a.whatHappens == b.whatHappens && a.position == b.position && a.targetWords == b.targetWords && a.number == b.number && a.refs == b.refs && a.proposedRefs == b.proposedRefs && a.dismissed == b.dismissed && a.proposal == b.proposal && a.continuity == b.continuity }
}

struct CreationBrief: Decodable, Sendable, Equatable {
    var setting: String?
    var who: String?
    var whatHappens: String?
    var readerLearns: String?
    var achieves: String?
}

struct CreationChapterDoc: Decodable, Sendable {
    struct Head: Decodable, Sendable {
        let id: Int
        let number: Int?
        let title: String?
        let creationStatus: String?
        let briefing: CreationBrief?
        let proseLock: Lock?
    }
    struct Lock: Decodable, Sendable { let applies: Bool?; let locked: Bool?; let warning: String? }
    struct BookHead: Decodable, Sendable { let id: Int; let title: String; let number: Int? }
    struct ActHead: Decodable, Sendable { let id: Int; let title: String?; let number: Int? }
    struct Scene: Decodable, Sendable, Identifiable { let id: Int; let beats: [CreationBeat] }
    struct Prose: Decodable, Sendable { let text: String?; let wordCount: Int?; let paragraphs: Int?; let hash: String? }
    let chapter: Head
    let book: BookHead?
    let act: ActHead?
    let scenes: [Scene]
    let beats: [CreationBeat]
    let prose: Prose?
    /// The manuscript's own bytes cut at the pending beats' places; joined end to end they are the chapter (0.55.0).
    let segments: [String]?

    /// A chapter past editing in a book at production or later is read-only.
    var proseLocked: Bool { chapter.proseLock?.applies == true && chapter.proseLock?.locked == true }
}

/// A change to a beat that Godric has drafted in the chapter conversation. Only Apply writes it.
struct BeatProposalCard: Decodable, Sendable, Identifiable, Equatable {
    struct BeatInfo: Decodable, Sendable, Equatable {
        let id: Int?
        let number: Int?
        let currentTargetWords: Int?
        let proposedTargetWords: Int?
    }
    let proposalId: String
    let conversationId: Int
    let status: String?
    let reason: String?
    let beat: BeatInfo?
    let currentBody: String
    let proposedBody: String
    var id: String { proposalId }
    var pending: Bool { status == nil }

    private enum Keys: String, CodingKey { case proposalId, conversationId, status, reason, beat, currentBody, proposedBody }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let s = try? c.decode(String.self, forKey: .proposalId) { proposalId = s }
        else { proposalId = String(try c.decode(Int.self, forKey: .proposalId)) }
        conversationId = try c.decode(Int.self, forKey: .conversationId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        beat = try c.decodeIfPresent(BeatInfo.self, forKey: .beat)
        currentBody = try c.decodeIfPresent(String.self, forKey: .currentBody) ?? ""
        proposedBody = try c.decodeIfPresent(String.self, forKey: .proposedBody) ?? ""
    }
}

struct CreationMessage: Decodable, Sendable {
    let id: Int
    let role: String
    let kind: String
    let text: String
    let createdAt: String?
    let proposal: BeatProposalCard?
}

struct CreationChat: Decodable, Sendable {
    let messages: [CreationMessage]
}

struct CreationReply: Decodable, Sendable {
    let text: String
    let pendingBeatChange: BeatProposalCard?
}

struct ReferenceCandidate: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
}

private struct Candidates: Decodable, Sendable { let entries: [ReferenceCandidate] }
private struct BriefBody: Encodable, Sendable { let fields: [String: String] }
private struct BriefResult: Decodable, Sendable { let briefing: CreationBrief? }
private struct InsertBeatBody: Encodable, Sendable {
    let position: Int?
    let what_happens: String
}
private struct InsertBeatResult: Decodable, Sendable { let beatId: Int? }
private struct BeatPatch: Encodable, Sendable {
    let what_happens: String
    let target_words: Int?
}
private struct ReorderBody: Encodable, Sendable { let ordered_ids: [Int] }
private struct NameBody: Encodable, Sendable { let name: String }
private struct RefItem: Encodable, Sendable { let name: String; let codex_id: Int?; let type: String? }
private struct RefsBody: Encodable, Sendable { let refs: [RefItem] }
private struct ProposalActBody: Encodable, Sendable { let conversation_id: Int; let proposal_id: String }
private struct Ignored: Decodable, Sendable {}

/// The Creation panel for one book at a time: the chapter picker, and one open chapter with its brief, beats and Godric
/// thread. The server holds everything; nothing is kept beyond this session and a chapter is read again on every open.
@MainActor @Observable
final class CreationModel {
    struct Banner: Equatable { let text: String; var isError = false }

    let godric = GodricModel(thread: .creation)

    // the picker
    var books: [CreationBookSummary] = []
    var bookId: Int?
    var bookDoc: CreationBookDoc?
    var loading = false
    var loadError: String?

    // an open chapter
    var chapterId: Int?
    var doc: CreationChapterDoc?
    var opening = false
    var openError: String?
    var banner: Banner?
    var working = false
    var busyBeats: Set<Int> = []

    // the brief, edited in place
    var briefEditing = false
    var briefDraft = CreationBrief()
    private var briefBase = CreationBrief()

    /// What Godric has drafted for a beat and the author has not yet applied.
    var proposal: BeatProposalCard?
    var candidates: [ReferenceCandidate] = []

    // prose: unsaved edits live here in memory only (ADR 0.55.0: the server is the only text store)
    var proseEdits: [String]?
    var editOrigin: [String] = []
    var editBase: EditBase?
    var beganSession = false
    var conflict: ProseConflict?
    var savingProse = false
    /// The last Accept, kept for this session so Undo can put things back.
    var lastAccept: AcceptResult?
    var generating: Set<Int> = []
    var stops: [Int: GenerationStop] = [:]
    var notes: [DraftingNote] = []
    var noteQuote: String?
    var locking = false
    /// The add/edit beat sheet, held here so the bottom actions can open it from the glass bar.
    var beatSheet: BeatSheetTarget?

    var client: APIClient?

    // MARK: status wording (the desktop's)

    static func statusLabel(_ status: String?, briefed: Bool? = true) -> String {
        switch status {
        case "draft_one": return "Draft one"
        case "drafting": return "Drafting"
        default: return briefed == false ? "Not briefed" : "Briefed"
        }
    }

    /// "Prologue" for front and back matter, "Ch N" for the rest, walking the book in order as the desktop does.
    static func badges(_ acts: [CreationAct]) -> [Int: String] {
        let sections = "prologue|epilogue|interlude|preface|foreword|afterword|coda"
        var out: [Int: String] = [:]
        var bodyN = 0
        for act in acts {
            let actIsSection = (act.title ?? "").trimmingCharacters(in: .whitespaces).range(of: "^(\(sections))\\b", options: [.regularExpression, .caseInsensitive]) != nil
            for c in act.chapters {
                let title = (c.title ?? "").trimmingCharacters(in: .whitespaces)
                if let m = title.range(of: "^(\(sections))\\b", options: [.regularExpression, .caseInsensitive]) {
                    out[c.id] = title[m].capitalized
                } else if let m = title.range(of: "^(?:chapter|ch)\\.?\\s*(\\d+)", options: [.regularExpression, .caseInsensitive]),
                          let n = Int(title[m].filter(\.isNumber)) {
                    bodyN = n; out[c.id] = "Ch \(n)"
                } else if actIsSection {
                    out[c.id] = (act.title ?? "").capitalized
                } else {
                    bodyN += 1; out[c.id] = "Ch \(bodyN)"
                }
            }
        }
        return out
    }

    // MARK: the picker

    func loadBooks(client: APIClient, preferred: Int) async {
        self.client = client
        godric.onBeatProposal = { [weak self] p in self?.proposal = p }
        loading = true; loadError = nil
        defer { loading = false }
        do {
            let r: CreationBooksResponse = try await client.get("/api/creation/books")
            books = r.books
            let chosen = r.books.first { $0.id == preferred }?.id ?? r.books.first?.id
            if chosen != bookId { bookDoc = nil }
            bookId = chosen
            if let chosen { try await readBook(chosen, client: client) }
        } catch {
            loadError = "Creation couldn't be opened."
        }
    }

    func selectBook(_ id: Int, client: APIClient) async {
        guard id != bookId else { return }
        bookId = id; bookDoc = nil
        loading = true; defer { loading = false }
        do { try await readBook(id, client: client); loadError = nil }
        catch { loadError = "This book's chapters couldn't be read." }
    }

    private func readBook(_ id: Int, client: APIClient) async throws {
        bookDoc = try await client.get("/api/creation/books/\(id)")
    }

    func reloadBook() async {
        guard let client, let bookId else { return }
        if let d: CreationBookDoc = try? await client.get("/api/creation/books/\(bookId)") { bookDoc = d }
    }

    // MARK: opening and leaving a chapter

    /// A deliberate open. As on the desktop, the server drops empty beats first, then opens the chapter (a briefed
    /// chapter becomes "drafting" as a side effect), and the chapter conversation is read.
    func open(_ id: Int, client: APIClient) async {
        self.client = client
        godric.resetCreation()
        chapterId = id; doc = nil; openError = nil; banner = nil; proposal = nil
        briefEditing = false
        discardEdits(); lastAccept = nil; stops = [:]; notes = []; beganSession = false; noteQuote = nil
        opening = true
        defer { opening = false }
        _ = try? await client.post("/api/creation/chapters/\(id)/prune-empty-beats", body: EmptyBody(), as: Ignored.self)
        do {
            doc = try await client.get("/api/creation/chapters/\(id)")
            await readChat(id, client: client)
            await loadNotes()
        } catch {
            openError = "This chapter couldn't be opened."
        }
    }

    /// Leaving a chapter drops any empty beat the author left behind.
    func close() async {
        guard let id = chapterId, let client else { chapterId = nil; return }
        chapterId = nil; doc = nil; proposal = nil; briefEditing = false
        discardEdits(); lastAccept = nil; stops = [:]; notes = []
        godric.resetCreation()
        _ = try? await client.post("/api/creation/chapters/\(id)/prune-empty-beats", body: EmptyBody(), as: Ignored.self)
        await reloadBook()
    }

    /// The app came back to the front: everything shown is read again, unless something is being edited.
    func refreshOnForeground() async {
        guard let client else { return }
        if let id = chapterId {
            if let d: CreationChapterDoc = try? await client.get("/api/creation/chapters/\(id)") { doc = d }
            if !godric.busy { await readChat(id, client: client) }
            await loadNotes()
        } else {
            await reloadBook()
        }
    }

    private func readChat(_ id: Int, client: APIClient) async {
        guard let chat: CreationChat = try? await client.get("/api/creation/chapters/\(id)/chat") else { return }
        godric.seedCreation(bookId: doc?.book?.id ?? bookId ?? 0, chapterId: id, title: doc?.chapter.title, messages: chat.messages)
        proposal = chat.messages.last(where: { $0.proposal?.pending == true })?.proposal
    }

    @discardableResult
    private func reloadChapter() async -> Bool {
        guard let client, let id = chapterId else { return false }
        do { doc = try await client.get("/api/creation/chapters/\(id)"); return true }
        catch { banner = Banner(text: "The chapter couldn't be read again.", isError: true); return false }
    }

    private func fail(_ what: String, _ error: Error) {
        banner = Banner(text: "\(what): \((error as? APIError)?.message ?? "could not reach the server")", isError: true)
    }

    // MARK: the brief

    var brief: CreationBrief { doc?.chapter.briefing ?? CreationBrief() }

    func beginBriefEdit() {
        briefDraft = brief; briefBase = brief; briefEditing = true; banner = nil
    }

    func cancelBriefEdit() { briefEditing = false }

    /// Only the fields the author changed are sent, so a field changed on the laptop meanwhile is not written back.
    func saveBrief() async {
        guard let client, let id = chapterId, briefEditing, !working else { return }
        var fields: [String: String] = [:]
        if briefDraft.setting != briefBase.setting { fields["setting"] = briefDraft.setting ?? "" }
        if briefDraft.who != briefBase.who { fields["who"] = briefDraft.who ?? "" }
        if briefDraft.whatHappens != briefBase.whatHappens { fields["what_happens"] = briefDraft.whatHappens ?? "" }
        if briefDraft.readerLearns != briefBase.readerLearns { fields["reader_learns"] = briefDraft.readerLearns ?? "" }
        if briefDraft.achieves != briefBase.achieves { fields["achieves"] = briefDraft.achieves ?? "" }
        if fields.isEmpty { briefEditing = false; return }
        working = true; defer { working = false }
        do {
            let _: BriefResult = try await client.patch("/api/creation/chapters/\(id)/briefing", body: BriefBody(fields: fields))
            briefEditing = false
            await reloadChapter()
            banner = Banner(text: "Brief saved.")
        } catch {
            fail("The brief wasn't saved. Your text is kept", error)
        }
    }

    // MARK: beats

    func paragraphs() -> [String] {
        (doc?.prose?.text ?? "").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func placeLabel(_ beat: CreationBeat) -> String {
        guard let pos = beat.position else { return "At the end of the chapter" }
        if pos == 0 { return "Before the first paragraph" }
        let paras = paragraphs()
        var snip = pos - 1 < paras.count ? paras[pos - 1].replacingOccurrences(of: "[*_]", with: "", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) : ""
        if snip.count > 70 { snip = String(snip.prefix(70)).replacingOccurrences(of: "\\s+\\S*$", with: "", options: .regularExpression) + "…" }
        return "After paragraph \(pos)" + (snip.isEmpty ? "" : ": “\(snip)”")
    }

    func addBeat(_ text: String, target: Int?, position: Int?) async -> Bool {
        guard let client, let id = chapterId, !working, requireSaved() else { return false }
        working = true; defer { working = false }
        do {
            let r: InsertBeatResult = try await client.post("/api/creation/chapters/\(id)/insert-beat", body: InsertBeatBody(position: position, what_happens: text))
            if let beatId = r.beatId, target != nil {
                let _: Ignored = try await client.patch("/api/creation/beats/\(beatId)", body: BeatPatch(what_happens: text, target_words: target))
            }
            await reloadChapter()
            return true
        } catch { fail("The beat wasn't added", error); return false }
    }

    func updateBeat(_ beat: CreationBeat, text: String, target: Int?) async -> Bool {
        guard let client, !working else { return false }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.patch("/api/creation/beats/\(beat.id)", body: BeatPatch(what_happens: text, target_words: target))
            await reloadChapter()
            return true
        } catch { fail("The beat wasn't saved", error); return false }
    }

    func deleteBeat(_ beat: CreationBeat) async {
        guard let client, !working, requireSaved() else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.delete("/api/creation/beats/\(beat.id)")
            await reloadChapter()
        } catch { fail("The beat wasn't deleted", error) }
    }

    func canMove(_ beat: CreationBeat, by step: Int) -> Bool {
        guard let scene = doc?.scenes.first(where: { $0.id == beat.sceneId }), let i = scene.beats.firstIndex(where: { $0.id == beat.id }) else { return false }
        return scene.beats.indices.contains(i + step)
    }

    func move(_ beat: CreationBeat, by step: Int) async {
        guard let client, !working, canMove(beat, by: step), requireSaved(),
              let scene = doc?.scenes.first(where: { $0.id == beat.sceneId }),
              let i = scene.beats.firstIndex(where: { $0.id == beat.id }) else { return }
        var ids = scene.beats.map(\.id)
        ids.swapAt(i, i + step)
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.post("/api/creation/scenes/\(scene.id)/reorder-beats", body: ReorderBody(ordered_ids: ids))
            await reloadChapter()
        } catch { fail("The beats weren't reordered", error) }
    }

    // MARK: references

    func proposeRefs(_ beat: CreationBeat) async {
        guard let client, !busyBeats.contains(beat.id) else { return }
        busyBeats.insert(beat.id); defer { busyBeats.remove(beat.id) }
        struct Proposed: Decodable { let proposed: [BeatRef]? }
        do {
            let _: Proposed = try await client.post("/api/creation/beats/\(beat.id)/propose-refs", body: EmptyBody())
            await reloadChapter()
        } catch { fail("References couldn't be proposed", error) }
    }

    func loadCandidates(for beat: CreationBeat) async {
        guard let client else { return }
        if let c: Candidates = try? await client.get("/api/creation/beats/\(beat.id)/ref-candidates") { candidates = c.entries }
    }

    /// Replaces the beat's reference list with exactly this one.
    func setRefs(_ beat: CreationBeat, _ refs: [BeatRef]) async {
        guard let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.put("/api/creation/beats/\(beat.id)/refs",
                body: RefsBody(refs: refs.map { RefItem(name: $0.name, codex_id: $0.codexId, type: $0.type) }))
            await reloadChapter()
        } catch { fail("The references weren't saved", error) }
    }

    func dismissRef(_ beat: CreationBeat, name: String, restore: Bool) async {
        guard let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.post("/api/creation/beats/\(beat.id)/\(restore ? "undismiss-ref" : "dismiss-ref")", body: NameBody(name: name))
            await reloadChapter()
        } catch { fail("The reference wasn't changed", error) }
    }

    func acceptContinuity(_ beat: CreationBeat) async {
        guard let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.post("/api/creation/beats/\(beat.id)/continuity/accept", body: EmptyBody())
            await reloadChapter()
        } catch { fail("That wasn't saved", error) }
    }

    // MARK: Godric's beat change

    func applyProposal() async {
        guard let proposal, let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.post("/api/creation/beat-proposal/apply",
                body: ProposalActBody(conversation_id: proposal.conversationId, proposal_id: proposal.proposalId))
            self.proposal = nil
            await reloadChapter()
            banner = Banner(text: "Applied. The beat is changed.")
        } catch APIError.http(409, _) {
            self.proposal = nil
            await reloadChapter()
            banner = Banner(text: "That change was already dealt with or is out of date. Ask Godric to draft it again.", isError: true)
        } catch { fail("Apply failed", error) }
    }

    func discardProposal() async {
        guard let proposal, let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: Ignored = try await client.post("/api/creation/beat-proposal/discard",
                body: ProposalActBody(conversation_id: proposal.conversationId, proposal_id: proposal.proposalId))
            self.proposal = nil
            banner = Banner(text: "Draft discarded. The beat is unchanged.")
        } catch APIError.http(409, _) {
            self.proposal = nil
        } catch { fail("Discard failed", error) }
    }
}

// MARK: - Sprint 3: generation, prose, drafting notes, lock (ADR 0.55.0)

struct EditBase: Equatable { let hash: String?; let beatIds: [Int] }

struct ProseConflict: Identifiable {
    enum Kind { case changed, beats }
    let id = UUID()
    let kind: Kind
    /// What the author typed, whole.
    let mine: String
    /// The server's text now (for `.changed`).
    let theirs: String
}

struct GenerationStop: Equatable {
    struct Gap: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        let reason: String?
        let type: String?
        var id: String { name }
    }
    struct Continuity: Decodable, Sendable, Equatable { let note: String? }
    var message: String
    var gaps: [Gap]
    var continuity: String?
}

private struct GenerateResult: Decodable, Sendable {
    let stopped: Bool?
    let message: String?
    let gaps: [GenerationStop.Gap]?
    let continuity: GenerationStop.Continuity?
    let wordCount: Int?
}

struct AcceptResult: Decodable, Sendable {
    struct BeatBack: Decodable, Sendable {
        let sceneId: Int?
        let whatHappens: String?
        let targetWords: Int?
        let position: Int?
        let refsJson: String?
    }
    let insertedParagraphs: Int?
    let undoVersionId: Int?
    let beat: BeatBack?
}

private struct UndoBody: Encodable, Sendable {
    struct Beat: Encodable, Sendable {
        let scene_id: Int?; let what_happens: String; let target_words: Int?; let position: Int?; let refs_json: String?
    }
    let undo_version_id: Int
    let inserted_paragraphs: Int
    let beat: Beat?
}

private struct ProseBody: Encodable, Sendable {
    let segments: [String]
    let beat_ids: [Int]
    let base_hash: String?
    let overwrite: Bool
    let begin_session: Bool
}

private struct ProseSaved: Decodable, Sendable { let saved: Bool?; let unchanged: Bool?; let proseWordCount: Int? }
private struct NotesResponse: Decodable, Sendable { let notes: [DraftingNote] }
private struct NewNote: Encodable, Sendable { let note_text: String; let anchor_quote: String? }
private struct NoteStatus: Encodable, Sendable { let status: String }
private struct LockResult: Decodable, Sendable { let wordCount: Int? }

struct DraftingNote: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let noteText: String
    let anchorQuote: String?
    let status: String
    var isOpen: Bool { status == "open" }
}

/// Finds a note's passage in the text. The passage was selected in rendered text, so italic and bold markers in the
/// manuscript are allowed between its words, and any run of white space matches.
enum NoteAnchor {
    static func range(of quote: String, in text: String) -> Range<String.Index>? {
        let words = quote.split(whereSeparator: \.isWhitespace).map(String.init)
        guard quote.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6, !words.isEmpty else { return nil }
        let pattern = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "[\\s*_]+")
        return text.range(of: pattern, options: .regularExpression)
    }
}

extension CreationModel {
    // MARK: edits in memory

    var segmentsShown: [String] { proseEdits ?? doc?.segments ?? [] }
    var dirty: Bool { proseEdits != nil && proseEdits! != editOrigin }
    var isLocked: Bool { doc?.proseLocked == true }

    /// An edit to one segment. The first edit remembers what it was made from (the hash and the beats shown), which is
    /// what the save sends, so a change made elsewhere meanwhile is caught by the server.
    func setSegment(_ i: Int, _ text: String) {
        guard !isLocked, var segs = proseEdits ?? doc?.segments, segs.indices.contains(i) else { return }
        if proseEdits == nil {
            editOrigin = segs
            editBase = EditBase(hash: doc?.prose?.hash, beatIds: (doc?.beats ?? []).map(\.id))
        }
        guard segs[i] != text else { return }
        segs[i] = text
        proseEdits = segs
        if noteQuote != nil { noteQuote = nil }
    }

    func discardEdits() { proseEdits = nil; editBase = nil; conflict = nil }

    /// Structural actions need the text saved first: they change what the segments are.
    func requireSaved() -> Bool {
        if dirty { banner = Banner(text: "Save or discard your edits first.", isError: true); return false }
        return true
    }

    // MARK: saving through the segment save

    func saveProse(overwrite: Bool = false) async {
        guard let client, let id = chapterId, let segs = proseEdits, let base = editBase, dirty, !savingProse else { return }
        savingProse = true; defer { savingProse = false }
        banner = nil
        do {
            let r: ProseSaved = try await client.put("/api/creation/chapters/\(id)/prose-with-beats",
                body: ProseBody(segments: segs, beat_ids: base.beatIds, base_hash: base.hash, overwrite: overwrite, begin_session: !beganSession))
            beganSession = true
            discardEdits()
            lastAccept = nil
            await reloadChapter()
            banner = Banner(text: r.unchanged == true ? "Nothing to save." : "Saved" + (r.proseWordCount.map { " · \($0.formatted()) words" } ?? "") + ".")
        } catch APIError.http(let code, let body) {
            let mine = segs.joined()
            switch code {
            case 409 where body.contains("BEATS_CHANGED"):
                await reloadChapter()
                conflict = ProseConflict(kind: .beats, mine: mine, theirs: "")
            case 409:
                let current: CreationChapterDoc? = try? await client.get("/api/creation/chapters/\(id)")
                conflict = ProseConflict(kind: .changed, mine: mine, theirs: current?.segments?.joined() ?? current?.prose?.text ?? "")
            case 423:
                await reloadChapter()
                banner = Banner(text: "This chapter is locked, so nothing was saved. What you typed is still on screen.", isError: true)
            case 400:
                banner = Banner(text: "A chapter can't be saved empty. What you typed is still on screen.", isError: true)
            default:
                banner = Banner(text: "Save failed: \(APIError.http(code, body).message). What you typed is still on screen.", isError: true)
            }
        } catch {
            fail("Save failed, and what you typed is still on screen", error)
        }
    }

    /// Keep what the author typed: the save is sent again, and the server first keeps the other text as a version.
    func keepMine() async {
        conflict = nil
        await saveProse(overwrite: true)
    }

    /// Use the server's text: the author's edits are dropped (copied first if asked).
    func useCurrent() async {
        conflict = nil
        discardEdits()
        await reloadChapter()
    }

    // MARK: generation

    func generate(_ beat: CreationBeat) async {
        guard let client, !generating.contains(beat.id), requireSaved() else { return }
        generating.insert(beat.id); defer { generating.remove(beat.id) }
        stops[beat.id] = nil
        banner = nil
        do {
            let r: GenerateResult = try await client.post("/api/creation/beats/\(beat.id)/generate", body: EmptyBody())
            if r.stopped == true {
                stops[beat.id] = GenerationStop(message: r.message ?? "Generation stopped.", gaps: r.gaps ?? [], continuity: r.continuity?.note)
            }
            await reloadChapter()
        } catch { fail("The draft couldn't be made", error) }
    }

    func clearStop(_ beat: CreationBeat) { stops[beat.id] = nil }

    func dismissGap(_ beat: CreationBeat, name: String) async {
        await dismissRef(beat, name: name, restore: false)
        stops[beat.id]?.gaps.removeAll { $0.name == name }
        if stops[beat.id]?.gaps.isEmpty == true, stops[beat.id]?.continuity == nil { stops[beat.id] = nil }
    }

    func acceptStoppedContinuity(_ beat: CreationBeat) async {
        await acceptContinuity(beat)
        stops[beat.id]?.continuity = nil
        if stops[beat.id]?.gaps.isEmpty == true { stops[beat.id] = nil }
    }

    func acceptDraft(_ beat: CreationBeat) async {
        guard let client, !working, requireSaved() else { return }
        working = true; defer { working = false }
        do {
            let r: AcceptResult = try await client.post("/api/creation/beats/\(beat.id)/accept", body: EmptyBody())
            lastAccept = r
            await reloadChapter()
            banner = Banner(text: "The draft is in the chapter. Undo last draft is available until you save an edit.")
        } catch { fail("The draft wasn't accepted", error) }
    }

    func discardDraft(_ beat: CreationBeat) async {
        guard let client, !working else { return }
        working = true; defer { working = false }
        do {
            let _: CreationBeat = try await client.post("/api/creation/beats/\(beat.id)/discard-proposal", body: EmptyBody())
            await reloadChapter()
        } catch { fail("The draft wasn't discarded", error) }
    }

    func undoLastDraft() async {
        guard let client, let id = chapterId, let a = lastAccept, let version = a.undoVersionId, !working, requireSaved() else { return }
        working = true; defer { working = false }
        let back = a.beat.map { UndoBody.Beat(scene_id: $0.sceneId, what_happens: $0.whatHappens ?? "", target_words: $0.targetWords, position: $0.position, refs_json: $0.refsJson) }
        do {
            struct Undone: Decodable { let chapterId: Int? }
            let _: Undone = try await client.post("/api/creation/chapters/\(id)/undo-draft",
                body: UndoBody(undo_version_id: version, inserted_paragraphs: a.insertedParagraphs ?? 0, beat: back))
            lastAccept = nil
            await reloadChapter()
            banner = Banner(text: "Undone. The chapter is back as it was, and the beat is back.")
        } catch { fail("Undo failed", error) }
    }

    // MARK: drafting notes

    func loadNotes() async {
        guard let client, let id = chapterId else { return }
        if let r: NotesResponse = try? await client.get("/api/chapters/\(id)/drafting-notes") { notes = r.notes }
    }

    var openNotes: [DraftingNote] { notes.filter(\.isOpen) }

    func isPlaced(_ note: DraftingNote) -> Bool {
        guard let q = note.anchorQuote, !q.isEmpty else { return true }
        return segmentsShown.contains { NoteAnchor.range(of: q, in: $0) != nil }
    }

    func addNote(_ text: String, quote: String?) async -> Bool {
        guard let client, let id = chapterId else { return false }
        do {
            let n: DraftingNote = try await client.post("/api/chapters/\(id)/drafting-notes", body: NewNote(note_text: text, anchor_quote: quote))
            notes.append(n)
            return true
        } catch { fail("The note wasn't saved", error); return false }
    }

    func setNote(_ note: DraftingNote, open: Bool) async {
        guard let client else { return }
        do {
            let n: DraftingNote = try await client.patch("/api/drafting-notes/\(note.id)", body: NoteStatus(status: open ? "open" : "cleared"))
            if let i = notes.firstIndex(where: { $0.id == n.id }) { notes[i] = n }
        } catch { fail("The note wasn't changed", error) }
    }

    func deleteNote(_ note: DraftingNote) async {
        guard let client else { return }
        do {
            struct Gone: Decodable { let deleted: Bool? }
            let _: Gone = try await client.delete("/api/drafting-notes/\(note.id)")
            notes.removeAll { $0.id == note.id }
        } catch { fail("The note wasn't deleted", error) }
    }

    // MARK: lock as draft one

    func lockDraft() async {
        guard let client, let id = chapterId, requireSaved(), !locking else { return }
        locking = true; defer { locking = false }
        do {
            let r: LockResult = try await client.post("/api/creation/chapters/\(id)/lock-draft", body: EmptyBody())
            lastAccept = nil
            await reloadChapter()
            banner = Banner(text: "Locked as draft one" + (r.wordCount.map { " — \($0.formatted()) words" } ?? "") + ". Eligible for the editing tower.")
        } catch { fail("The chapter wasn't locked", error) }
    }
}
