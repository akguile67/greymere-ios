// THROWAWAY prototype state (ADR 0.59.0 Sprint 1): everything lives in memory, nothing is sent anywhere.
import SwiftUI

struct Hit: Identifiable {
    enum Why { case name, alias(String), text }
    let entry: Entry
    let why: Why
    var id: Int { entry.id }
    var whyText: String {
        switch why { case .name: "name match"; case .alias(let a): "alias: \(a)"; case .text: "text match" }
    }
}

struct Proposal {
    var entryID: Int
    var baseVersion: Int
    var name: String
    var aliases: [String]
    var body: String
    var series: [String]? = nil
    var books: [String]? = nil
    var origin = "Edit"
}

enum EntryAction: Hashable { case edit, dictate, standardise, image, books, delete }

@MainActor @Observable
final class CodexStore {
    var entries: [Entry] = DummyCodex.make()
    var scope: String? = "The Route"            // nil = all series
    var showContained = false
    var recents: [Int] = [1, 2]
    var godricContext: Int?
    var currentEntry: Int?
    var pendingAction: EntryAction?
    var newToken = 0
    var ipadPortraitDrill = true
    var landscape = false
    var selection: Int?
    var fullScreen = false
    var leftWidth: CGFloat = 360
    var nextID = 10_000

    func index(_ id: Int) -> Int? { entries.firstIndex { $0.id == id } }
    func entry(_ id: Int) -> Entry? { index(id).map { entries[$0] } }
    func children(of id: Int) -> [Entry] { entries.filter { $0.parent == id } }
    func descendantCount(_ id: Int) -> Int { children(of: id).reduce(0) { $0 + 1 + descendantCount($1.id) } }
    func ancestors(of e: Entry) -> [Entry] {
        var out: [Entry] = []; var cur = e
        while let p = cur.parent, let pe = entry(p) { out.insert(pe, at: 0); cur = pe }
        return out
    }
    func building(of e: Entry) -> Entry? { ancestors(of: e).first }

    var inScope: [Entry] { scope == nil ? entries : entries.filter { $0.series.contains(scope!) } }

    func count(_ t: EType?) -> Int { inScope.filter { t == nil || $0.type == t } .count }

    /// The list for a type: the fold hides rooms and floors inside a building unless the switch is on.
    func list(type: EType?, query: String) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return search(q, type: type) }
        return inScope.filter { ($0.type == type || type == nil) && (showContained || $0.parent == nil) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { Hit(entry: $0, why: .name) }
    }

    /// Ranked: exact name, exact alias, whole word in name or alias, word prefix, substring, then body text.
    /// Search ignores the fold: rooms always appear.
    func search(_ q: String, type: EType?) -> [Hit] {
        let q = q.lowercased()
        func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
        var scored: [(Int, Hit)] = []
        for e in inScope where type == nil || e.type == type {
            let n = e.name.lowercased()
            let aliasHit: (String, Int)? = e.aliases.compactMap { a -> (String, Int)? in
                let l = a.lowercased(); let w = words(a)
                if l == q { return (a, 1) }; if w.contains(q) { return (a, 2) }; if w.contains(where: { $0.hasPrefix(q) }) { return (a, 3) }; if l.contains(q) { return (a, 4) }
                return nil
            }.min { $0.1 < $1.1 }
            let nameRank: Int? = n == q ? 0 : words(n).contains(q) ? 2 : words(n).contains(where: { $0.hasPrefix(q) }) ? 3 : n.contains(q) ? 4 : nil
            switch (nameRank, aliasHit) {
            case (let nr?, let ah?): scored.append((min(nr, ah.1), Hit(entry: e, why: nr <= ah.1 ? .name : .alias(ah.0))))
            case (let nr?, nil): scored.append((nr, Hit(entry: e, why: .name)))
            case (nil, let ah?): scored.append((ah.1, Hit(entry: e, why: .alias(ah.0))))
            default: if e.body.lowercased().contains(q) { scored.append((9, Hit(entry: e, why: .text))) }
            }
        }
        return scored.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element.1)
    }

    func touch(_ id: Int) { recents.removeAll { $0 == id }; recents.insert(id, at: 0); recents = Array(recents.prefix(6)) }

    func apply(_ p: Proposal) {
        guard let i = index(p.entryID) else { return }
        entries[i].name = p.name; entries[i].aliases = p.aliases; entries[i].body = p.body
        if let s = p.series { entries[i].series = s }
        if let b = p.books { entries[i].books = b }
        entries[i].version += 1; entries[i].edited = "just now"
    }

    func create(name: String, type: EType, aliases: [String], body: String) -> Int {
        nextID += 1
        entries.append(Entry(id: nextID, name: name, type: type, aliases: aliases, body: body, role: "", parent: nil,
                             series: [scope ?? "Standalone"], books: [], image: .none, edited: "just now"))
        return nextID
    }

    func delete(_ id: Int) { entries.removeAll { $0.id == id || $0.parent == id }; recents.removeAll { $0 == id }; if godricContext == id { godricContext = nil } }
}

/// Line diff for the proposal screen.
enum DiffKind { case same, add, del }
struct DiffLine: Identifiable { let id = UUID(); let kind: DiffKind; let text: String }

func lineDiff(old: String, new: String) -> [DiffLine] {
    let o = old.components(separatedBy: "\n"), n = new.components(separatedBy: "\n")
    let d = n.difference(from: o)
    var removed = Set<Int>(), inserted = Set<Int>()
    for c in d { switch c { case .remove(let off, _, _): removed.insert(off); case .insert(let off, _, _): inserted.insert(off) } }
    var out: [DiffLine] = []; var i = 0, j = 0
    while i < o.count || j < n.count {
        if i < o.count, removed.contains(i) { out.append(.init(kind: .del, text: o[i])); i += 1 }
        else if j < n.count, inserted.contains(j) { out.append(.init(kind: .add, text: n[j])); j += 1 }
        else { out.append(.init(kind: .same, text: i < o.count ? o[i] : n[j])); i += 1; j += 1 }
    }
    return out
}
