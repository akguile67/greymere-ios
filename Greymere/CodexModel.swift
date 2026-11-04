import Foundation
import Observation

// The Codex panel (ADR 0.59.0). Read-only in this first slice: the list, search, browse by type, and an entry with
// its aliases, books, and (when the server sends parents) the buildings and rooms around it.

/// The server's entry types, as `codex_entries.type` holds them.
enum CodexType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case characters, locations, objects, lore, research, voiceGuide = "voice_guide", referenceList = "reference_list", other

    var id: String { rawValue }
    init(server: String) { self = CodexType(rawValue: server) ?? .other }

    var title: String {
        switch self {
        case .characters: "Characters"; case .locations: "Locations"; case .objects: "Objects"; case .lore: "Lore"; case .research: "Research"
        case .voiceGuide: "Voice guides"; case .referenceList: "Reference lists"; case .other: "Other"
        }
    }
    var single: String {
        switch self {
        case .characters: "Character"; case .locations: "Location"; case .objects: "Object"; case .lore: "Lore"; case .research: "Research"
        case .voiceGuide: "Voice guide"; case .referenceList: "Reference list"; case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .characters: "person.fill"; case .locations: "building.columns.fill"; case .objects: "key.fill"; case .lore: "scroll.fill"; case .research: "magnifyingglass"
        case .voiceGuide: "mic.fill"; case .referenceList: "list.bullet.rectangle.fill"; case .other: "tray.fill"
        }
    }
}

/// One row of `GET /api/codex`. `aliases` and `parentId` arrive once the server sends them (0.59.0); until then they are
/// empty and every location is a root.
struct CodexEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let typeName: String
    let body: String?
    let portraitPath: String?
    let portraitStatus: String?
    let updatedAt: String?
    let nodeKind: String?
    let childCount: Int?
    let aliasCount: Int?
    let aliases: [String]?
    let parentId: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, typeName = "type", body, portraitPath, portraitStatus, updatedAt, nodeKind, childCount, aliasCount, aliases, parentId
    }

    var type: CodexType { CodexType(server: typeName) }
    var allAliases: [String] { aliases ?? [] }
    var snippet: String { body ?? "" }

    /// The `- **Role**: …` line some characters carry, for the second line of a row.
    var role: String {
        for line in snippet.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: "**Role**:", options: .caseInsensitive) { return String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        }
        return ""
    }
}

struct CodexBookRef: Decodable, Hashable, Sendable {
    let bookId: Int?
    let bookTitle: String?
    let bookNumber: Int?
}

/// `GET /api/codex/:id`: the whole entry.
struct CodexDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let type: String
    let body: String?
    let seriesId: Int?
    let updatedAt: String?
    let aliases: [String]?
    let appearancesByBook: [CodexBookRef]?
    let portraitPath: String?
    let portraitStatus: String?
    /// The books the author set the entry to feature in (not the chapters it is linked from).
    let bookIds: [Int]?
    let chains: [CodexChain]?
}

struct CodexBook: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let number: Int?
    let title: String
    let seriesId: Int?
    let seriesName: String?
}

/// A top-level Series (Crime Fiction, Historical Fiction, ...). The server calls it a chain.
struct CodexChain: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}
private struct CodexChains: Decodable, Sendable { let chains: [CodexChain] }
private struct CodexTag: Encodable {}
struct CodexCraft: Decodable, Sendable { let prompt: String }
struct CodexGenerated: Decodable, Sendable { let imageUrl: String; let costUsd: Double?; let ms: Int? }
private struct CodexPromptBody: Encodable { let prompt: String }
private struct CodexUrlBody: Encodable { let url: String }
private struct CodexOk: Decodable, Sendable { let ok: Bool? }
private struct CodexStandardised: Decodable, Sendable { let proposedBody: String; let level: String? }

/// A Book series (Greymere, Ellen's Story, ...): the server's `series` row.
struct CodexSeries: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

/// A search hit and why it matched.
struct CodexHit: Identifiable {
    enum Why { case name, alias(String), text }
    let entry: CodexEntry
    let why: Why
    var id: Int { entry.id }
}

private struct CodexSave: Encodable {
    let name: String
    let body: String
    let aliases: [String]
    let baseUpdatedAt: String
    let seriesId: Int?
    let bookIds: [Int]?
    private enum CodingKeys: String, CodingKey { case name, body, aliases, baseUpdatedAt = "base_updated_at", seriesId = "series_id", bookIds = "book_ids" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(body, forKey: .body); try c.encode(aliases, forKey: .aliases)
        try c.encode(baseUpdatedAt, forKey: .baseUpdatedAt)
        try c.encode(seriesId, forKey: .seriesId)          // null clears the series
        try c.encodeIfPresent(bookIds, forKey: .bookIds)
    }
}
private struct CodexSaved: Decodable { let id: Int }
private struct CodexNew: Encodable {
    let name: String; let type: String; let body: String; let aliases: [String]; let seriesId: Int?; let bookIds: [Int]?; let chainIds: [Int]
    private enum CodingKeys: String, CodingKey { case name, type, body, aliases, seriesId = "series_id", bookIds = "book_ids", chainIds = "chain_ids" }
}
private struct CodexDeleted: Decodable { let ok: Bool? }

struct CodexFailure: Error { let text: String }

enum CodexApplyResult { case saved, stale(CodexDetail), failed(String) }

@MainActor @Observable
final class CodexModel {
    var series: [CodexSeries] = []
    var books: [CodexBook] = []
    var chains: [CodexChain] = []
    private(set) var chainId: Int?
    /// nil = every series.
    private(set) var seriesId: Int?
    var entries: [CodexEntry] = []
    var loading = false
    var loadError: String?
    var showContained = false
    var selection: Int?
    var recents: [Int] = []
    var details: [Int: CodexDetail] = [:]
    var banner: String?
    /// Landscape: the width of the menu column, and full screen (the panel alone).
    var leftWidth: CGFloat = 360
    var fullScreen = false
    var landscape = false
    /// The menu's drill-down and search live here, not in the view, so turning the device keeps them.
    var menuPath: [CodexRoute] = []
    var query = ""

    private var client: APIClient?
    private static let chainKey = "greymere.codexChainId"
    private static let seriesKey = "greymere.codexSeriesId"
    private static let recentsKey = "greymere.codexRecents"

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.seriesKey)
        seriesId = saved == 0 ? nil : saved
        recents = (UserDefaults.standard.array(forKey: Self.recentsKey) as? [Int]) ?? []
        let c = UserDefaults.standard.integer(forKey: Self.chainKey)
        chainId = c == 0 ? nil : c
    }

    func start(client: APIClient) async {
        self.client = client
        if series.isEmpty, let s: [CodexSeries] = try? await client.get("/api/series") {
            series = s
            if let id = seriesId, !s.contains(where: { $0.id == id }) { seriesId = nil }
            if seriesId == nil && UserDefaults.standard.object(forKey: Self.seriesKey) == nil, let first = s.first { seriesId = first.id }
        }
        if chains.isEmpty, let c: CodexChains = try? await client.get("/api/chains") {
            chains = c.chains
            if let id = chainId, !c.chains.contains(where: { $0.id == id }) { chainId = nil }
        }
        await reload()
    }

    /// Picks the top-level Series to show (nil = all) and remembers it.
    func chooseChain(_ id: Int?) {
        chainId = id
        UserDefaults.standard.set(id ?? 0, forKey: Self.chainKey)
        Task { await reload() }
    }

    /// Picks the series to show (nil = all) and remembers it.
    func chooseSeries(_ id: Int?) {
        seriesId = id
        UserDefaults.standard.set(id ?? 0, forKey: Self.seriesKey)
        Task { await reload() }
    }

    func reload() async {
        guard let client else { return }
        loading = true; defer { loading = false }
        var q: [String] = []
        if let seriesId { q.append("series_id=\(seriesId)") }
        if let chainId { q.append("chain_id=\(chainId)") }
        let path = "/api/codex" + (q.isEmpty ? "" : "?" + q.joined(separator: "&"))
        do {
            entries = try await client.get(path)
            loadError = nil
        } catch let e as APIError { loadError = e.message } catch { loadError = "The Codex could not be read." }
    }

    // MARK: images (the server calls them portraits)

    /// Runs one image action, then reads the entry again so the picture and its status are current. Returns an error
    /// message, or nil on success.
    private func portraitCall(_ id: Int, _ work: (APIClient) async throws -> Void) async -> String? {
        guard let client else { return "Not connected." }
        do { try await work(client) } catch let e as APIError { return e.message } catch { return "That did not work." }
        await refreshDetail(id); await reload()
        return nil
    }
    func uploadPortrait(_ id: Int, jpeg: Data) async -> String? {
        await portraitCall(id) { let _: CodexOk = try await $0.postRaw("/api/codex/\(id)/portrait?ext=jpg", data: jpeg, contentType: "image/jpeg") }
    }
    func approvePortrait(_ id: Int) async -> String? { await portraitCall(id) { let _: CodexOk = try await $0.post("/api/codex/\(id)/portrait/approve", body: CodexTag()) } }
    func rejectPortrait(_ id: Int) async -> String? { await portraitCall(id) { let _: CodexOk = try await $0.post("/api/codex/\(id)/portrait/reject", body: CodexTag()) } }
    func deletePortrait(_ id: Int) async -> String? { await portraitCall(id) { let _: CodexOk = try await $0.delete("/api/codex/\(id)/portrait") } }
    func savePortrait(_ id: Int, url: String) async -> String? {
        await portraitCall(id) { let _: CodexOk = try await $0.post("/api/codex/\(id)/portrait/save", body: CodexUrlBody(url: url)) }
    }
    /// Godric writes the prompt for the image (a short model call, no image yet).
    func craftPrompt(_ id: Int) async -> Result<String, CodexFailure> {
        guard let client else { return .failure(CodexFailure(text: "Not connected.")) }
        do { let c: CodexCraft = try await client.post("/api/codex/\(id)/portrait/craft-prompt", body: CodexTag()); return .success(c.prompt) }
        catch let e as APIError { return .failure(CodexFailure(text: e.message)) } catch { return .failure(CodexFailure(text: "That did not work.")) }
    }
    /// Makes the image. This is the step that costs money (about $0.04) and takes about 15 seconds.
    func generatePortrait(_ id: Int, prompt: String) async -> Result<CodexGenerated, CodexFailure> {
        guard let client else { return .failure(CodexFailure(text: "Not connected.")) }
        do { let g: CodexGenerated = try await client.post("/api/codex/\(id)/portrait/generate", body: CodexPromptBody(prompt: prompt)); return .success(g) }
        catch let e as APIError { return .failure(CodexFailure(text: e.message)) } catch { return .failure(CodexFailure(text: "That did not work.")) }
    }

    /// A server image path made into an address, for the list thumbnails.
    func imageURL(_ path: String?) -> URL? { client?.asset(path) }

    /// Asks the server to reorganise a location's text under its template's headings. Nothing is written: the result is
    /// a proposal for the editor.
    func standardise(_ id: Int) async -> Result<String, CodexFailure> {
        guard let client else { return .failure(CodexFailure(text: "Not connected.")) }
        do { let r: CodexStandardised = try await client.post("/api/codex/\(id)/standardise", body: CodexTag()); return .success(r.proposedBody) }
        catch let e as APIError { return .failure(CodexFailure(text: e.message)) } catch { return .failure(CodexFailure(text: "That did not work.")) }
    }

    func loadBooks() async {
        guard let client, books.isEmpty, let b: [CodexBook] = try? await client.get("/api/books") else { return }
        books = b
    }

    /// Follows the server's change notices. A reload on every (re)connect catches what happened while the app was
    /// asleep; `codex.changed` (once the server sends it) catches an entry added or edited on another device.
    func listen(client: APIClient) async {
        var pending: Task<Void, Never>?
        for await name in ServerEvents.stream(client: client) {
            guard name == "connected" || name == "codex.changed" else { continue }
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                self.details = [:]
                await self.reload()
                if let id = self.selection { await self.loadDetail(id) }
            }
        }
    }

    /// Reads an entry again, whatever is cached, so an edit made on another device shows. An entry the server no longer
    /// has is dropped here too (deleted elsewhere).
    func refreshDetail(_ id: Int) async {
        guard let client else { return }
        do {
            let d: CodexDetail = try await client.get("/api/codex/\(id)")
            details[id] = d
            if let i = entries.firstIndex(where: { $0.id == id }), entries[i].updatedAt != d.updatedAt { await reload() }
        } catch APIError.badStatus(404) {
            entries.removeAll { $0.id == id }; details[id] = nil
            if selection == id { selection = nil }
            menuPath.removeAll { $0 == .entry(id) }
        } catch {}
    }

    /// Until the server announces Codex changes (`codex.changed`), look again every so often while the panel is open, so
    /// what another device adds, edits or deletes turns up without leaving the panel.
    func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { break }
            await reload()
            if let id = selection { await refreshDetail(id) }
            else if case .entry(let id)? = menuPath.last { await refreshDetail(id) }
        }
    }

    func loadDetail(_ id: Int) async {
        guard let client, details[id] == nil else { return }
        if let d: CodexDetail = try? await client.get("/api/codex/\(id)") { details[id] = d }
    }

    /// Writes an edit the author has reviewed. The entry is read again first: if it changed since the edit began, nothing
    /// is written (and the server, once it carries the same guard, refuses too).
    func apply(id: Int, name: String, aliases: [String], body: String, series: Int?, bookIds: [Int]?, chainIds: Set<Int>, baseChains: Set<Int>, baseStamp: String, client: APIClient) async -> CodexApplyResult {
        do {
            let now: CodexDetail = try await client.get("/api/codex/\(id)")
            if (now.updatedAt ?? "") != baseStamp { details[id] = now; return .stale(now) }
            let _: CodexSaved = try await client.put("/api/codex/\(id)", body: CodexSave(name: name, body: body, aliases: aliases, baseUpdatedAt: baseStamp, seriesId: series, bookIds: bookIds))
            // Series membership is its own set of routes: add before removing, because the server never lets an entry
            // lose its last Series.
            for c in chainIds.subtracting(baseChains) { let _: CodexDeleted = try await client.post("/api/chains/\(c)/codex/\(id)", body: CodexTag()) }
            for c in baseChains.subtracting(chainIds) { let _: CodexDeleted = try await client.delete("/api/chains/\(c)/codex/\(id)") }
            details[id] = nil
            await loadDetail(id)
            await reload()
            banner = "Saved."
            return .saved
        } catch APIError.http(409, _) {
            if let now: CodexDetail = try? await client.get("/api/codex/\(id)") { details[id] = now; return .stale(now) }
            return .failed("This entry changed since you opened it.")
        } catch let e as APIError { return .failed(e.message) } catch { return .failed("The change could not be saved.") }
    }

    /// Creates an entry. Returns its id.
    func create(name: String, type: CodexType, aliases: [String], body: String, series: Int?, bookIds: [Int]?, chainIds: Set<Int>, client: APIClient) async -> Int? {
        do {
            let saved: CodexSaved = try await client.post("/api/codex", body: CodexNew(name: name, type: type.rawValue, body: body, aliases: aliases, seriesId: series, bookIds: bookIds, chainIds: Array(chainIds).sorted()))
            await reload()
            return saved.id
        } catch { return nil }
    }

    /// Deletes an entry for good (the server removes its aliases, links and image) and forgets it here.
    func delete(_ id: Int, client: APIClient) async -> Bool {
        do {
            let _: CodexDeleted = try await client.delete("/api/codex/\(id)")
            entries.removeAll { $0.id == id }; details[id] = nil
            recents.removeAll { $0 == id }; UserDefaults.standard.set(recents, forKey: Self.recentsKey)
            if selection == id { selection = nil }
            menuPath.removeAll { $0 == .entry(id) }
            return true
        } catch { return false }
    }

    // MARK: reading the list

    var scopeName: String {
        let c = chainId.flatMap { id in chains.first { $0.id == id }?.name }
        let b = seriesId.flatMap { id in series.first { $0.id == id }?.name }
        switch (c, b) { case (nil, nil): return "All series"; case (let c?, nil): return c; case (nil, let b?): return b; case (let c?, let b?): return "\(c) · \(b)" }
    }

    func entry(_ id: Int) -> CodexEntry? { entries.first { $0.id == id } }
    func count(_ type: CodexType?) -> Int { type == nil ? entries.count : entries.filter { $0.type == type }.count }
    func children(of id: Int) -> [CodexEntry] { entries.filter { $0.parentId == id }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    func descendantCount(_ id: Int) -> Int { children(of: id).reduce(0) { $0 + 1 + descendantCount($1.id) } }
    func ancestors(of e: CodexEntry) -> [CodexEntry] {
        var out: [CodexEntry] = []; var cur = e; var guardN = 0
        while let p = cur.parentId, let pe = entry(p), guardN < 20 { out.insert(pe, at: 0); cur = pe; guardN += 1 }
        return out
    }
    func building(of e: CodexEntry) -> CodexEntry? { ancestors(of: e).first }

    /// A type's list. The fold hides rooms and floors inside a building unless the switch is on.
    func list(type: CodexType, query: String) -> [CodexHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return search(q, type: type) }
        return entries.filter { $0.type == type && (showContained || $0.parentId == nil) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { CodexHit(entry: $0, why: .name) }
    }

    /// Ranked: exact name, exact alias, whole word, word prefix, substring, then body text. Search ignores the fold.
    func search(_ query: String, type: CodexType?) -> [CodexHit] {
        let q = query.lowercased()
        func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
        var scored: [(Int, CodexHit)] = []
        for e in entries where type == nil || e.type == type {
            let n = e.name.lowercased()
            let aliasHit: (String, Int)? = e.allAliases.compactMap { a -> (String, Int)? in
                let l = a.lowercased(); let w = words(a)
                if l == q { return (a, 1) }; if w.contains(q) { return (a, 2) }; if w.contains(where: { $0.hasPrefix(q) }) { return (a, 3) }; if l.contains(q) { return (a, 4) }
                return nil
            }.min { $0.1 < $1.1 }
            let nameRank: Int? = n == q ? 0 : words(n).contains(q) ? 2 : words(n).contains(where: { $0.hasPrefix(q) }) ? 3 : n.contains(q) ? 4 : nil
            switch (nameRank, aliasHit) {
            case (let nr?, let ah?): scored.append((min(nr, ah.1), CodexHit(entry: e, why: nr <= ah.1 ? .name : .alias(ah.0))))
            case (let nr?, nil): scored.append((nr, CodexHit(entry: e, why: .name)))
            case (nil, let ah?): scored.append((ah.1, CodexHit(entry: e, why: .alias(ah.0))))
            default: if e.snippet.lowercased().contains(q) { scored.append((9, CodexHit(entry: e, why: .text))) }
            }
        }
        return scored.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element.1)
    }

    /// Turning the device swaps the portrait drill-down for the split view. An entry open in one is carried to the other:
    /// full screen in landscape becomes the entry page in portrait, and an entry page in portrait becomes the selection.
    func rotated(toLandscape l: Bool) {
        landscape = l
        if l {
            if case .entry(let id)? = menuPath.last { selection = id; menuPath.removeLast() }
        } else if fullScreen {
            fullScreen = false
            if let id = selection, entry(id) != nil, menuPath.last != .entry(id) { menuPath.append(.entry(id)) }
        }
    }

    func touch(_ id: Int) {
        recents.removeAll { $0 == id }; recents.insert(id, at: 0); recents = Array(recents.prefix(6))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }
}
