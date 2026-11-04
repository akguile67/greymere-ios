// THROWAWAY prototype state (ADR 0.60.0 Sprint 2): everything lives in memory, nothing is sent anywhere.
import SwiftUI

enum CState: String { case notBriefed = "Not briefed", active = "Active", briefed = "Briefed" }

let fieldNames = ["Summary headline", "Setting", "Who", "What happens", "What the reader learns", "What it achieves"]

struct PChapter: Identifiable, Equatable {
    let id: String
    var number: Int
    var title: String
    var state: CState
    var fields: [String]
    var gaps: [String] = []
    var drafted = false
    var staged = false
    var summary: String { fields[0] }
}

struct PAct: Identifiable {
    let id: String
    var label: String
    var title: String
    var synopsis: String
    var locked: Bool
    var chapters: [PChapter]
    var briefed: Int { chapters.filter { $0.state == .briefed }.count }
    var draftedCount: Int { chapters.filter(\.drafted).count }
    var badge: String {
        if chapters.isEmpty { return "Not started" }
        if locked && draftedCount == chapters.count { return "Drafted" }
        return "In progress"
    }
    var outstanding: (String, String)? {
        if !locked { return ("Synopsis to lock", "lock it in Ideation") }
        if chapters.isEmpty { return ("No chapters yet", "add the chapters this act needs") }
        if briefed < chapters.count { return ("Briefs outstanding", "\(chapters.count - briefed) to brief") }
        if draftedCount < chapters.count { return ("Prose outstanding", "\(chapters.count - draftedCount) to draft") }
        return nil
    }
}

enum ProtoSheet: Identifiable {
    case add(String), delete(String), rename(String), stale(String)
    var id: String {
        switch self { case .add(let a): "add\(a)"; case .delete(let c): "del\(c)"; case .rename(let c): "ren\(c)"; case .stale(let c): "stale\(c)" }
    }
}

struct StaleDiff: Identifiable { let id = UUID(); let field: Int; let mine: String; let theirs: String }

struct GMessage: Identifiable {
    enum Kind { case me, godric, staged(String), codex }
    let id = UUID(); let kind: Kind; var text: String
}

@MainActor @Observable
final class StructureStore {
    var books = ["The Route", "The House", "The Cold Quay"]
    var book = "The Route"
    var acts: [PAct] = DummyStructure.make()
    var openAct: String? = "act1"
    var path: [String] = []          // phone drill-down
    var selected: String? = nil      // iPad landscape split
    var isSplit = false
    var sheet: ProtoSheet?
    var toast: String?
    var banner: String?
    var armStale = false
    var staleDiffs: [StaleDiff] = []
    var godricOpen = false
    var thread: [GMessage] = [GMessage(kind: .godric, text: "Structure is open. Tell me which chapter to brief, or ask about the book.")]
    var codexApplied: Bool? = nil
    var synopsisOpen: Set<String> = []

    var currentChapterID: String? { isSplit ? selected : path.last }
    var emptyBook: Bool { book == "The House" }
    var draftedActs: Int { acts.filter { $0.badge == "Drafted" }.count }

    func chapter(_ id: String) -> PChapter? { acts.flatMap(\.chapters).first { $0.id == id } }
    func actIndex(of cid: String) -> Int? { acts.firstIndex { $0.chapters.contains { $0.id == cid } } }
    func act(of cid: String) -> PAct? { actIndex(of: cid).map { acts[$0] } }
    func mutate(_ cid: String, _ f: (inout PChapter) -> Void) {
        guard let a = actIndex(of: cid), let c = acts[a].chapters.firstIndex(where: { $0.id == cid }) else { return }
        f(&acts[a].chapters[c])
    }
    func renumber() { var n = 1; for a in acts.indices { for c in acts[a].chapters.indices { acts[a].chapters[c].number = n; n += 1 } } }

    func toggleAct(_ id: String) { withAnimation(.snappy) { openAct = openAct == id ? nil : id } }   // one act open at a time
    func open(_ cid: String) {
        mutate(cid) { if $0.state == .notBriefed && !$0.fields.joined().isEmpty { $0.state = .active } }
        if isSplit { selected = cid } else { path = [cid] }
    }
    func say(_ t: String) {
        toast = t
        Task { try? await Task.sleep(for: .seconds(3)); if toast == t { toast = nil } }
    }
    func flash(_ t: String) {
        banner = t
        Task { try? await Task.sleep(for: .seconds(4)); if banner == t { banner = nil } }
    }

    func add(to actID: String, title: String) {
        guard let a = acts.firstIndex(where: { $0.id == actID }) else { return }
        let t = title.trimmingCharacters(in: .whitespaces)
        acts[a].chapters.append(PChapter(id: UUID().uuidString, number: 0, title: t.isEmpty ? "Untitled chapter" : t, state: .notBriefed, fields: Array(repeating: "", count: 6)))
        renumber(); openAct = actID
        say("Added. Later chapters moved up by one.")
    }
    func delete(_ cid: String) {
        guard let a = actIndex(of: cid) else { return }
        acts[a].chapters.removeAll { $0.id == cid }
        renumber(); path = []; if selected == cid { selected = nil }
        say("Chapter deleted. Later chapters renumbered.")
    }
    func rename(_ cid: String, _ t: String) { mutate(cid) { $0.title = t.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled chapter" : t } }

    func move(_ cid: String, onto target: String) {
        guard cid != target, let a = actIndex(of: cid), let b = actIndex(of: target) else { return }
        guard a == b else { say("A chapter stays in its act. To move it, delete it and add it in the other act."); return }
        let from = acts[a].chapters.firstIndex { $0.id == cid }!, to = acts[a].chapters.firstIndex { $0.id == target }!
        withAnimation(.snappy) { acts[a].chapters.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to) }
        renumber(); say("Moved. Numbers renumbered.")
    }
    func refuseDrop(_ cid: String, onAct actID: String) {
        if act(of: cid)?.id != actID { say("A chapter stays in its act. To move it, delete it and add it in the other act.") }
    }

    func setField(_ cid: String, _ i: Int, _ v: String) {
        mutate(cid) { c in
            guard c.state != .briefed else { return }
            c.fields[i] = v
            if c.state == .notBriefed && !v.isEmpty { c.state = .active }
        }
    }
    func commit(_ cid: String) {
        guard let c = chapter(cid) else { return }
        if c.fields.allSatisfy(\.isEmpty) { say("Nothing to commit: the briefing is empty."); return }
        if armStale {
            armStale = false
            var d: [StaleDiff] = []
            let theirs = [1: "Open sea, fog.", 5: "Commits Marenne; opens the crossing."]
            for (i, t) in theirs where c.fields[i] != t { d.append(StaleDiff(field: i, mine: c.fields[i].isEmpty ? "(empty)" : c.fields[i], theirs: t)) }
            if d.isEmpty { d = [StaleDiff(field: 1, mine: c.fields[1], theirs: "Open sea, fog.")] }
            staleDiffs = d.sorted { $0.field < $1.field }; sheet = .stale(cid); return
        }
        mutate(cid) { $0.state = .briefed; $0.staged = false }
        say("Briefing committed.")
    }
    func resolveStale(_ cid: String, useThisDevice: Bool) {
        if useThisDevice { mutate(cid) { $0.state = .briefed; $0.staged = false }; say("Saved from this device.") }
        else { for d in staleDiffs { mutate(cid) { $0.fields[d.field] = d.theirs } }; say("Kept the other device's version.") }
        sheet = nil
    }
    func unlock(_ cid: String) { mutate(cid) { $0.state = .active }; say("Unlocked. Edit, then Commit.") }

    func send(_ text: String) {
        thread.append(GMessage(kind: .me, text: text))
        let target = currentChapterID ?? acts[1].chapters.first(where: { $0.state != .briefed })?.id
        guard let t = target, let c = chapter(t) else { thread.append(GMessage(kind: .godric, text: "Open a chapter first.")); return }
        if c.state == .briefed { thread.append(GMessage(kind: .godric, text: "Chapter \(c.number) is Briefed. Unlock it first and I will stage a brief.")); return }
        mutate(t) { c in
            c.fields = ["The night run: Marenne takes the Tern out with Cass at the helm.", "Open sea, no moon, running dark.", "Marenne, Cass.", "They cross the bar without lights; a patrol boat passes close.", "Cass can handle a boat.", "Gets the Tern into open water and sets up the landing."]
            c.state = .active; c.staged = true; c.gaps = ["Cass's Honda CX"]
        }
        thread.append(GMessage(kind: .godric, text: "Staged a brief on chapter \(c.number). Review and commit it on the card."))
        thread.append(GMessage(kind: .staged(t), text: ""))
        thread.append(GMessage(kind: .godric, text: "I also drafted a codex entry for the missing Honda."))
        thread.append(GMessage(kind: .codex, text: ""))
        codexApplied = nil
    }

    func simulateLive() {
        guard let t = acts[0].chapters.first ?? acts[1].chapters.first else { return }
        mutate(t.id) { $0.fields[0] = "Updated on the desktop: " + $0.fields[0] }
        flash("Chapter \(t.number) changed on another device. Updated.")
    }
    func reset() { acts = DummyStructure.make(); openAct = "act1"; path = []; selected = nil; toast = nil; banner = nil; armStale = false; synopsisOpen = [] }
}

enum DummyStructure {
    static func ch(_ title: String, _ state: CState, drafted: Bool = false, gaps: [String] = [], _ summary: String = "") -> PChapter {
        let f: [String] = state == .notBriefed && summary.isEmpty ? Array(repeating: "", count: 6) :
            [summary, "Harrow Quay, 4 a.m., fog.", "Marenne, the harbour master, Cass.", "The master reads the order aloud; Marenne cuts the line.", "The cargo is not what the manifest says.", "Commits Marenne; opens the crossing."]
        return PChapter(id: UUID().uuidString, number: 0, title: title, state: state, fields: f, gaps: gaps, drafted: drafted)
    }
    static let syn = "Marenne takes the Tern out of Harrow Quay against the harbour master's order, and the town learns what the cargo is. This is a reminder of intent only; it changes in Ideation. The act closes with the Tern gone from the quay and the harbour master left holding a signed order nobody will obey."
    static func make() -> [PAct] {
        var acts = [
            PAct(id: "pro", label: "Prologue", title: "The Letter", synopsis: syn, locked: true, chapters: [ch("The Letter", .briefed, drafted: true, "A letter arrives at the quay.")]),
            PAct(id: "act1", label: "Act 1", title: "The Quay", synopsis: syn, locked: true, chapters: [
                ch("The Quay at Dawn", .briefed, drafted: true, "Marenne wakes to the tide table."),
                ch("The Harbour Master", .briefed, drafted: true, gaps: ["The Section 78 Ruling"], "Marenne is refused clearance."),
                ch("Night Crossing", .active, "Setting and who filled in."),
                ch("The Cellar Door", .briefed, "Cass shows her the cellar."),
                ch("Untitled chapter", .notBriefed)]),
            PAct(id: "act2", label: "Act 2", title: "The Crossing", synopsis: syn, locked: true, chapters: [
                ch("Open Water", .briefed, "The Tern clears the bar."), ch("The Patrol", .briefed, "A boat shadows them.")]),
            PAct(id: "act3", label: "Act 3", title: "The Landing", synopsis: syn, locked: false, chapters: []),
            PAct(id: "epi", label: "Epilogue", title: "After", synopsis: syn, locked: false, chapters: []),
        ]
        var n = 1; for a in acts.indices { for c in acts[a].chapters.indices { acts[a].chapters[c].number = n; n += 1 } }
        return acts
    }
}
