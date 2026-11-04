import Foundation
import Observation

// The Structure panel (ADR 0.60.0, iOS 0.10.0). The acts come from the locked book synopsis and are read-only here; the
// author adds chapters to each act, briefs each on six fields (a summary headline and five more), drags the chapter
// cards to reorder them within their act, and talks to Godric about them in the book's one Structure thread.

struct StructureBriefing: Decodable, Sendable, Equatable {
    let setting: String?
    let who: String?
    let whatHappens: String?
    let readerLearns: String?
    let achieves: String?
}

struct StructureWarning: Decodable, Sendable, Equatable { let name: String }

struct StructureChapter: Decodable, Identifiable, Sendable, Equatable {
    let id: Int
    let version: String?
    let actId: Int
    let number: Int
    let title: String
    let summary: String?
    let structureStatus: String
    let briefing: StructureBriefing
    let codexWarning: [StructureWarning]?

    var isBriefed: Bool { structureStatus == "briefed" }
    var isActive: Bool { structureStatus == "active" }
    var stateLabel: String { isBriefed ? "Briefed" : isActive ? "Active" : "Not briefed" }
}

/// The six fields of a briefing: the headline summary, and the five the server calls setting, who, what happens,
/// what the reader learns and what it achieves.
enum BriefField: String, CaseIterable, Identifiable, Sendable {
    case summary, setting, who, whatHappens = "what_happens", readerLearns = "reader_learns", achieves
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: "Summary headline"; case .setting: "Setting"; case .who: "Who"; case .whatHappens: "What happens"
        case .readerLearns: "What the reader learns"; case .achieves: "What it achieves"
        }
    }
    func value(in c: StructureChapter) -> String {
        switch self {
        case .summary: c.summary ?? ""; case .setting: c.briefing.setting ?? ""; case .who: c.briefing.who ?? ""
        case .whatHappens: c.briefing.whatHappens ?? ""; case .readerLearns: c.briefing.readerLearns ?? ""; case .achieves: c.briefing.achieves ?? ""
        }
    }
}

struct StructureAct: Decodable, Identifiable, Sendable, Equatable {
    let id: Int
    let number: Int
    let label: String
    let title: String
    let locked: Bool
    let synopsis: String?
    let synopsisLocked: Bool
    let wordTarget: Double?
    let chapterCount: Int
    let orderVersion: String?
    let briefedCount: Int
    let draftedCount: Int
    let outstanding: String?
    let chapters: [StructureChapter]

    var badge: String { locked ? "Drafted" : chapters.isEmpty ? "Not started" : "In progress" }
    /// What is still open, most fundamental first, with the hint the desktop gives.
    var outstandingLine: (String, String)? {
        switch outstanding {
        case "synopsis": ("Synopsis to lock", "lock it in Ideation")
        case "chapters": ("No chapters yet", "add the chapters this act needs")
        case "briefs": ("Briefs outstanding", "\(chapters.count - briefedCount) to brief")
        case "prose": ("Prose outstanding", "\(chapters.count - draftedCount) to draft")
        default: nil
        }
    }
}

struct StructureDoc: Decodable, Sendable {
    struct Book: Decodable, Sendable { let id: Int; let title: String }
    let book: Book
    let lockedSynopsis: Bool
    let acts: [StructureAct]
}

struct StructureFootprint: Decodable, Sendable {
    struct Counts: Decodable, Sendable { let words: Int; let beats: Int; let issues: Int; let proofNotes: Int; let codexLinks: Int }
    let counts: Counts
    let renumber: Int
    var sentence: String {
        let c = counts
        var parts = ["\(c.words) words", "\(c.beats) beats", "\(c.issues) issues", "\(c.proofNotes) proof notes", "\(c.codexLinks) codex links"]
        parts.removeAll { $0.hasPrefix("0 ") }
        let what = parts.isEmpty ? "Nothing is written in it yet." : "This removes " + parts.joined(separator: ", ") + "."
        return what + (renumber > 0 ? " \(renumber) later chapters renumber." : "")
    }
}

/// A save, commit or rename the server refused because the chapter changed elsewhere: your text beside the card as it is now.
struct StructureConflict: Identifiable {
    struct Diff: Identifiable { let field: BriefField; let mine: String; let theirs: String; var id: String { field.id } }
    let id = UUID()
    let chapterId: Int
    let diffs: [Diff]
    let current: StructureChapter
    let thenCommit: Bool
}

enum StructureSheet: Identifiable {
    case add(Int), rename(Int), delete(Int)
    var id: String { switch self { case .add(let a): "add\(a)"; case .rename(let c): "ren\(c)"; case .delete(let c): "del\(c)" } }
}

struct StructureBanner: Identifiable { let id = UUID(); let text: String }

private struct SaveBody: Encodable { let fields: [String: String]; let baseVersion: String?
    private enum CodingKeys: String, CodingKey { case fields, baseVersion = "base_version" } }
private struct RenameBody: Encodable { let title: String; let baseVersion: String?
    private enum CodingKeys: String, CodingKey { case title, baseVersion = "base_version" } }
private struct ReorderBody: Encodable { let orderedIds: [Int]; let baseOrderVersion: String?
    private enum CodingKeys: String, CodingKey { case orderedIds = "ordered_ids", baseOrderVersion = "base_order_version" } }
private struct Added: Decodable, Sendable { let chapterId: Int? }
private struct Wrapped: Decodable, Sendable { let chapter: StructureChapter? }
private struct Ack: Decodable, Sendable { init(from decoder: Decoder) throws {} }
private struct StaleReply: Decodable, Sendable { let error: String?; let current: StructureChapter? }
private struct ConversationDoc: Decodable, Sendable { let messages: [StructureServerMessage] }

@MainActor @Observable
final class StructureModel {
    var bookId: Int?
    var doc: StructureDoc?
    var loading = false
    var loadError: String?
    var openAct: Int?
    var openActSynopsis: Set<Int> = []
    /// The open chapter (the split's right pane, or the pushed screen).
    var chapterId: Int?
    var sheet: StructureSheet?
    var conflict: StructureConflict?
    var banner: StructureBanner?
    var footprint: StructureFootprint?
    var busy = false
    /// What the author has typed on cards and not yet saved, by chapter then field.
    var edits: [Int: [BriefField: String]] = [:]
    /// Chapters Godric staged a brief on and the author has not committed.
    var staged: Set<Int> = []
    let godric = GodricModel(thread: .structure)

    private var client: APIClient?
    private var eventsTask: Task<Void, Never>?

    var chapter: StructureChapter? { chapterId.flatMap { chapter($0) } }
    func chapter(_ id: Int) -> StructureChapter? { doc?.acts.lazy.flatMap(\.chapters).first { $0.id == id } }
    func act(of chapterId: Int) -> StructureAct? { doc?.acts.first { $0.chapters.contains { $0.id == chapterId } } }
    var draftedActs: Int { doc?.acts.filter(\.locked).count ?? 0 }

    // MARK: reading

    func load(books: [ShelfItem], preferred: Int, client: APIClient) async {
        self.client = client
        godric.structureFocus = { [weak self] in self?.chapterId }
        godric.onStructureTurn = { [weak self] staged in await self?.afterGodricTurn(staged: staged) }
        let chosen = books.first { $0.rawId == preferred }?.rawId ?? books.first?.rawId
        guard let chosen else { return }
        if chosen != bookId { doc = nil; chapterId = nil; openAct = nil }
        bookId = chosen
        await reload()
        await loadThread()
        startEvents()
    }

    func select(book id: Int) async {
        guard id != bookId, let client else { return }
        bookId = id; doc = nil; chapterId = nil; openAct = nil; edits = [:]; staged = []
        godric.resetStructure()
        await reload()
        await loadThread()
        _ = client
    }

    func reload() async {
        guard let client, let bookId else { return }
        loading = doc == nil
        defer { loading = false }
        do {
            let d: StructureDoc = try await client.get("/api/structure/books/\(bookId)")
            doc = d
            loadError = nil
            if openAct == nil { openAct = d.acts.first { !$0.chapters.isEmpty && !$0.locked }?.id ?? d.acts.first { !$0.chapters.isEmpty }?.id }
            if let c = chapterId, chapter(c) == nil { chapterId = nil }
            for (id, _) in edits where chapter(id) == nil { edits[id] = nil }
        } catch {
            if doc == nil { loadError = "Structure couldn't be opened." }
        }
    }

    private func loadThread() async {
        guard let client, let bookId else { return }
        if let r: ConversationDoc = try? await client.get("/api/structure/books/\(bookId)/conversation") {
            godric.seedStructure(bookId: bookId, title: doc?.book.title, messages: r.messages)
        }
    }

    /// Looks again whenever the server says Structure changed (the desktop, or the other device), and when the stream
    /// (re)opens, because what happened while it was down is not replayed.
    private func startEvents() {
        guard eventsTask == nil, let client else { return }
        eventsTask = Task { [weak self] in
            var first = true
            for await name in ServerEvents.stream(client: client) {
                guard let self else { return }
                if name == "structure.changed" || (name == "connected" && !first) {
                    let before = self.doc
                    await self.reload()
                    if name == "structure.changed", self.busy == false, before != nil, self.doc?.acts != before?.acts {
                        self.say("Structure changed on another device. Updated.")
                    }
                }
                if name == "connected" { first = false }
            }
        }
    }

    func stopEvents() { eventsTask?.cancel(); eventsTask = nil }

    // MARK: banner

    func say(_ text: String) {
        let b = StructureBanner(text: text)
        banner = b
        Task { try? await Task.sleep(for: .seconds(4)); if banner?.id == b.id { banner = nil } }
    }

    // MARK: acts

    func toggleAct(_ id: Int) { withAnimationSnappy { openAct = openAct == id ? nil : id } }
    func toggleSynopsis(_ id: Int) {
        withAnimationSnappy { if openActSynopsis.contains(id) { openActSynopsis.remove(id) } else { openActSynopsis.insert(id) } }
    }
    private func withAnimationSnappy(_ body: () -> Void) { body() }

    // MARK: chapters

    func open(_ id: Int) async {
        chapterId = id
        if chapter(id)?.structureStatus == "empty", let client {
            let _: Ack? = try? await client.post("/api/structure/chapters/\(id)/open", body: EmptyBody())
            await reload()
        }
    }

    func text(_ c: StructureChapter, _ f: BriefField) -> String { edits[c.id]?[f] ?? f.value(in: c) }
    func setText(_ c: StructureChapter, _ f: BriefField, _ v: String) {
        guard !c.isBriefed else { return }
        if v == f.value(in: c) { edits[c.id]?[f] = nil; if edits[c.id]?.isEmpty == true { edits[c.id] = nil } }
        else { edits[c.id, default: [:]][f] = v }
    }
    func hasEdits(_ id: Int) -> Bool { !(edits[id]?.isEmpty ?? true) }

    /// Saves what was typed on a card without committing it (the card editor's save on leaving a field).
    func save(_ id: Int) async {
        guard let client, let c = chapter(id), let e = edits[id], !e.isEmpty else { return }
        do {
            let _: Ack = try await client.patch("/api/structure/chapters/\(id)/briefing",
                body: SaveBody(fields: Dictionary(uniqueKeysWithValues: e.map { ($0.key.rawValue, $0.value) }), baseVersion: c.version))
            edits[id] = nil
            await reload()
        } catch let error as APIError {
            if await handleStale(error, id: id, thenCommit: false) { return }
            say(error.message)
        } catch { say("That did not save.") }
    }

    func commit(_ id: Int) async {
        guard let client, let c = chapter(id) else { return }
        let fields = Dictionary(uniqueKeysWithValues: BriefField.allCases.map { ($0.rawValue, text(c, $0)) })
        if fields.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { say("Nothing to commit: the briefing is empty."); return }
        busy = true; defer { busy = false }
        struct Body: Encodable { let fields: [String: String]; let baseVersion: String?
            private enum CodingKeys: String, CodingKey { case fields, baseVersion = "base_version" } }
        do {
            let _: Ack = try await client.post("/api/structure/chapters/\(id)/commit", body: Body(fields: fields, baseVersion: c.version))
            edits[id] = nil; staged.remove(id)
            await reload()
        } catch let error as APIError {
            if await handleStale(error, id: id, thenCommit: true) { return }
            say(error.message)
        } catch { say("That did not commit.") }
    }

    func unlock(_ id: Int) async {
        guard let client else { return }
        let _: Ack? = try? await client.post("/api/structure/chapters/\(id)/reopen-briefing", body: EmptyBody())
        await reload()
    }

    func rename(_ id: Int, to title: String) async {
        guard let client, let c = chapter(id) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: Ack = try await client.patch("/api/structure/chapters/\(id)", body: RenameBody(title: t.isEmpty ? "Untitled chapter" : t, baseVersion: c.version))
            await reload()
        } catch let error as APIError {
            if case .http(409, _) = error { await reload(); say("That chapter changed elsewhere. Its current title is shown.") } else { say(error.message) }
        } catch { say("That did not rename.") }
    }

    /// Adds a chapter to the end of an act with the title the author gave. Later chapters renumber on the server.
    func addChapter(to actId: Int, title: String) async {
        guard let client else { return }
        busy = true; defer { busy = false }
        do {
            let r: Added = try await client.post("/api/structure/acts/\(actId)/chapters", body: EmptyBody())
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = r.chapterId, !t.isEmpty { let _: Ack? = try? await client.patch("/api/structure/chapters/\(id)", body: RenameBody(title: t, baseVersion: nil)) }
            openAct = actId
            await reload()
            say("Chapter added. Later chapters moved up by one.")
        } catch { say("The chapter could not be added.") }
    }

    func loadFootprint(_ id: Int) async {
        footprint = nil
        if let client { footprint = try? await client.get("/api/structure/chapters/\(id)/delete-footprint") }
    }

    func delete(_ id: Int) async {
        guard let client else { return }
        do {
            let _: Ack = try await client.delete("/api/structure/chapters/\(id)")
            if chapterId == id { chapterId = nil }
            edits[id] = nil
            await reload()
            say("Chapter deleted. Later chapters renumbered.")
        } catch { say("The chapter could not be deleted.") }
    }

    /// Hold-and-drop: puts `id` where `target` is, in the same act. Another act refuses with a message.
    func move(_ id: Int, onto target: Int) async {
        guard id != target, let client, let a = act(of: id) else { return }
        guard let ta = act(of: target), ta.id == a.id else {
            say("A chapter stays in its act. To move it, delete it and add it in the other act."); return
        }
        var ids = a.chapters.map(\.id)
        let from = ids.firstIndex(of: id)!, to = ids.firstIndex(of: target)!
        ids.remove(at: from); ids.insert(id, at: to)
        do {
            let _: Ack = try await client.post("/api/structure/acts/\(a.id)/reorder", body: ReorderBody(orderedIds: ids, baseOrderVersion: a.orderVersion))
            await reload()
        } catch let error as APIError {
            if case .http(409, _) = error { await reload(); say("That act's order changed elsewhere. Showing the current order.") } else { say(error.message) }
        } catch { say("That did not reorder.") }
    }

    func refuseDrop(_ id: Int, onAct actId: Int) {
        if act(of: id)?.id != actId { say("A chapter stays in its act. To move it, delete it and add it in the other act.") }
    }

    // MARK: stale writes

    private func handleStale(_ error: APIError, id: Int, thenCommit: Bool) async -> Bool {
        guard case .http(409, let body) = error, let data = body.data(using: .utf8) else { return false }
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        guard let r = try? d.decode(StaleReply.self, from: data), r.error == "stale", let current = r.current else { return false }
        var diffs: [StructureConflict.Diff] = []
        for f in BriefField.allCases {
            let mine = edits[id]?[f] ?? f.value(in: chapter(id) ?? current)
            let theirs = f.value(in: current)
            if mine != theirs { diffs.append(.init(field: f, mine: mine, theirs: theirs)) }
        }
        await reload()
        conflict = StructureConflict(chapterId: id, diffs: diffs, current: current, thenCommit: thenCommit)
        return true
    }

    /// One choice for the whole card. "This device" keeps the typed text and writes it over the current card.
    func resolve(_ c: StructureConflict, useThisDevice: Bool) async {
        conflict = nil
        if useThisDevice {
            // The card has been reloaded, so its version is current again; send what was typed.
            edits[c.chapterId] = Dictionary(uniqueKeysWithValues: c.diffs.map { ($0.field, $0.mine) })
            if c.thenCommit { await commit(c.chapterId) } else { await save(c.chapterId) }
        } else {
            edits[c.chapterId] = nil
        }
    }

    // MARK: Godric

    private func afterGodricTurn(staged chapterId: Int?) async {
        await reload()
        if let chapterId { staged.insert(chapterId); edits[chapterId] = nil }
    }
}
