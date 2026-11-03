// THROWAWAY prototype sheets (ADR 0.59.0 Sprint 1): stubs that show where each screen lives. Nothing is sent anywhere.
import SwiftUI

// MARK: Edit → proposal diff → Apply (or refused as stale)

struct EditSheet: View {
    enum Mode { case edit(Int, dictate: Bool), new(prefillName: String, type: EType, onCreated: (Int) -> Void) }
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var onDone: () -> Void
    @State private var name = ""
    @State private var type: EType = .character
    @State private var aliasText = ""
    @State private var bodyText = ""
    @State private var base = 1
    @State private var proposal: Proposal?
    @State private var loaded = false

    private var isNew: Bool { if case .new = mode { true } else { false } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $name) }
                Section("Also known as (comma-separated)") { TextField("Aliases", text: $aliasText) }
                Section("Type") {
                    if let e = existing, e.type.locked { Label("\(e.type.single) — fixed once set", systemImage: "lock.fill").foregroundStyle(.secondary) }
                    else {
                        Picker("Type", selection: $type) { ForEach(EType.allCases) { Text($0.single).tag($0) } }
                        if type.locked { Text("Voice guides and reference lists can’t change type once saved.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    TextEditor(text: $bodyText).frame(minHeight: 200)
                    Button { bodyText += (bodyText.isEmpty ? "" : "\n\n") + "The east shutters stay closed because of what happened in the second winter." } label: { Label("Dictate (prototype: inserts a sentence)", systemImage: "mic") }
                } header: { Text("Body (Markdown)") }
                if !isNew {
                    Section("Series and books") { Text("Edited from the ⋯ menu → Series, books, scope…").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(isNew ? "New entry" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isNew { Button("Create") { create() }.disabled(name.isEmpty) }
                    else { Button("Review") { review() }.disabled(name.isEmpty) }
                }
            }
            .navigationDestination(item: $proposal) { p in ProposalView(proposal: p, onDone: { dismiss(); onDone() }) }
            .onAppear(perform: load)
        }
    }

    private var existing: Entry? { if case .edit(let id, _) = mode { store.entry(id) } else { nil } }

    private func load() {
        guard !loaded else { return }; loaded = true
        switch mode {
        case .edit(let id, let dictate):
            guard let e = store.entry(id) else { return }
            name = e.name; type = e.type; aliasText = e.aliases.joined(separator: ", "); bodyText = e.body; base = e.version
            if dictate { bodyText += "\n\n(dictated) The east shutters stay closed because of the second winter." }
        case .new(let n, let t, _): name = n; type = t
        }
    }
    private var aliases: [String] { aliasText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private func review() {
        guard case .edit(let id, _) = mode else { return }
        proposal = Proposal(entryID: id, baseVersion: base, name: name, aliases: aliases, body: bodyText)
    }
    private func create() {
        guard case .new(_, _, let done) = mode else { return }
        let id = store.create(name: name, type: type, aliases: aliases, body: bodyText)
        dismiss(); done(id)
    }
}

extension Proposal: Identifiable, Hashable {
    var id: Int { entryID }
    static func == (a: Proposal, b: Proposal) -> Bool { a.entryID == b.entryID && a.baseVersion == b.baseVersion && a.body == b.body && a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(entryID); h.combine(baseVersion) }
}

struct ProposalView: View {
    @Environment(CodexStore.self) private var store
    @State var proposal: Proposal
    var onDone: () -> Void
    @State private var staleRefused = false

    var body: some View {
        let e = store.entry(proposal.entryID)
        List {
            Section { Text("\(proposal.origin) · based on the entry as of version \(proposal.baseVersion)").font(.footnote).foregroundStyle(.secondary) }
            if staleRefused, let e {
                Section {
                    Label("This entry changed after the proposal was made. Your change was not applied.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text("Now in the Codex (v\(e.version)): " + e.body.components(separatedBy: "\n").last!).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let e {
                if e.name != proposal.name { Section("Name") { diffRow(.init(kind: .del, text: e.name)); diffRow(.init(kind: .add, text: proposal.name)) } }
                let added = proposal.aliases.filter { !e.aliases.contains($0) }, removed = e.aliases.filter { !proposal.aliases.contains($0) }
                if !added.isEmpty || !removed.isEmpty { Section("Also known as") { ForEach(removed, id: \.self) { diffRow(.init(kind: .del, text: $0)) }; ForEach(added, id: \.self) { diffRow(.init(kind: .add, text: $0)) } } }
                let lines = lineDiff(old: e.body, new: proposal.body)
                Section("Body") {
                    if lines.allSatisfy({ $0.kind == .same }) { Text("No change to the body.").foregroundStyle(.secondary) }
                    else { ForEach(collapse(lines)) { diffRow($0) } }
                }
            }
            Section {
                HStack {
                    Button("Discard", role: .cancel) { onDone() }.buttonStyle(.bordered)
                    Spacer()
                    if staleRefused { Button("Re-propose on latest") { proposal.baseVersion = e?.version ?? 1; staleRefused = false }.buttonStyle(.borderedProminent) }
                    else { Button("Apply") { apply() }.buttonStyle(.borderedProminent) }
                }.listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Proposed change").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu { Button("Prototype: pretend it was edited on another device") { if let i = store.index(proposal.entryID) { store.entries[i].body += "\nCellar door added."; store.entries[i].version += 1 } } } label: { Image(systemName: "hammer") }
            }
        }
    }

    private func apply() {
        guard let e = store.entry(proposal.entryID) else { return }
        if e.version != proposal.baseVersion { staleRefused = true; return }   // stale edit refused
        store.apply(proposal); onDone()
    }
    private func collapse(_ l: [DiffLine]) -> [DiffLine] {
        var out: [DiffLine] = []; var run: [DiffLine] = []
        func flush() { if run.count > 3 { out.append(.init(kind: .same, text: "… \(run.count) unchanged lines")) } else { out += run }; run = [] }
        for x in l { if x.kind == .same { run.append(x) } else { flush(); out.append(x) } }
        flush(); return out
    }
    private func diffRow(_ d: DiffLine) -> some View {
        HStack(alignment: .top) {
            Text(d.kind == .add ? "+" : d.kind == .del ? "−" : " ").font(.body.monospaced())
            Text(d.text).strikethrough(d.kind == .del).font(.callout)
        }
        .foregroundStyle(d.kind == .add ? Color.green : d.kind == .del ? Color.red : Color.secondary)
        .listRowBackground(d.kind == .add ? Color.green.opacity(0.12) : d.kind == .del ? Color.red.opacity(0.12) : nil)
    }
}

struct StandardiseSheet: View {
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    var onDone: () -> Void
    @State private var proposal: Proposal?
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("A model reorganises this location’s text into the location template. Nothing is saved; the result lands on the same diff-and-Apply screen.").font(.callout).foregroundStyle(.secondary)
                if proposal == nil { ProgressView("Working… (prototype: instant)") }
            }.padding()
            .navigationTitle("Standardise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(item: $proposal) { ProposalView(proposal: $0, onDone: { dismiss(); onDone() }) }
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                guard let e = store.entry(id) else { return }
                let t = "## Overview\n" + e.body.replacingOccurrences(of: "**Overview**\n", with: "") .replacingOccurrences(of: "**Notes**", with: "## Atmosphere")
                var p = Proposal(entryID: id, baseVersion: e.version, name: e.name, aliases: e.aliases, body: t); p.origin = "Standardise to template"
                proposal = p
            }
        }
    }
}

// MARK: Image

struct ImageSheet: View {
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var prompt = "A grey sandstone house above a quay at dusk, a cold courtyard, shutters closed."
    @State private var generating = false
    @State private var generated = false
    @State private var confirmCost = false
    var body: some View {
        NavigationStack {
            Form {
                let e = store.entry(id)
                Section("Current image") {
                    RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)).frame(height: 140)
                        .overlay { Text(generated ? "New image — Use it, Regenerate or Discard" : e?.image == .none ? "none" : e?.image == .pending ? "pending review" : "approved").foregroundStyle(.secondary) }
                    if generated {
                        Button("Use it") { set(.pending); dismiss() }; Button("Regenerate") { confirmCost = true }; Button("Discard", role: .destructive) { generated = false }
                    } else if e?.image != .none {
                        Button("Approve") { set(.approved) }; Button("Reject") { set(.none) }; Button("Delete image", role: .destructive) { set(.none) }
                    }
                }
                Section("Make a new one") {
                    Button { prompt = "Godric’s crafted prompt: \(store.entry(id)?.name ?? "") in low winter light, painterly." } label: { Label("Craft prompt with Godric", systemImage: "sparkles") }
                    TextEditor(text: $prompt).frame(minHeight: 90)
                    Button { confirmCost = true } label: { Label(generating ? "Generating… (~15 s)" : "Generate", systemImage: "wand.and.rays") }.disabled(generating)
                }
                Section("Or use your own") {
                    Label("Photo library", systemImage: "photo.on.rectangle"); Label("Camera", systemImage: "camera")
                }
            }
            .navigationTitle("Image").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Generate an image?", isPresented: $confirmCost, titleVisibility: .visible) {
                Button("Generate (costs one run)") { generating = true; Task { try? await Task.sleep(for: .seconds(1)); generating = false; generated = true } }
            } message: { Text("Takes about 15 seconds and spends money on the image model.") }
        }
    }
    private func set(_ s: ImageState) { if let i = store.index(id) { store.entries[i].image = s } }
}

// MARK: Series, books, scope

struct BooksSheet: View {
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var series: Set<String> = []
    @State private var books: Set<String> = []
    @State private var open: Set<String> = []
    var body: some View {
        NavigationStack {
            List {
                Section("Series (chain)") {
                    ForEach(DummyCodex.series, id: \.name) { s in
                        Button { if series.contains(s.name) { series.remove(s.name) } else { series.insert(s.name) } } label: { HStack { Text(s.name); Spacer(); if series.contains(s.name) { Image(systemName: "checkmark") } } }.foregroundStyle(.primary)
                    }
                }
                if let e = store.entry(id), e.type == .character || e.type == .location {
                    Section("Appears in") {
                        ForEach(DummyCodex.series, id: \.name) { s in
                            DisclosureGroup(isExpanded: Binding(get: { open.contains(s.name) }, set: { if $0 { open.insert(s.name) } else { open.remove(s.name) } })) {
                                ForEach(s.books, id: \.self) { b in
                                    Button { if books.contains(b) { books.remove(b) } else { books.insert(b) } } label: { HStack { Text(b); Spacer(); if books.contains(b) { Image(systemName: "checkmark") } } }.foregroundStyle(.primary)
                                }
                                HStack { Button("All") { books.formUnion(s.books) }; Spacer(); Button("None") { books.subtract(s.books) } }.buttonStyle(.borderless)
                            } label: { Text(s.name).bold() }
                        }
                    }
                }
                Section { Text("Changes show as added or removed chips on the diff-and-Apply screen. (Prototype: applies directly.)").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Series and books").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let i = store.index(id) { store.entries[i].series = DummyCodex.series.map(\.name).filter(series.contains); store.entries[i].books = DummyCodex.books.filter(books.contains) }; dismiss() } }
            }
            .onAppear { if let e = store.entry(id) { series = Set(e.series); books = Set(e.books); open = Set(e.series) } }
        }
    }
}

// MARK: Find missing

struct FindMissingView: View {
    @Environment(CodexStore.self) private var store
    @State private var book = DummyCodex.books[1]
    @State private var items: [GapItem] = []
    @State private var scanned = false
    @State private var scanning = false
    @State private var tab = 0
    @State private var developing: GapItem?
    @State private var linking: GapItem?

    var body: some View {
        List {
            Section {
                Picker("Book", selection: $book) { ForEach(DummyCodex.books, id: \.self) { Text($0).tag($0) } }
                Button { scan() } label: { Label(scanning ? "Scanning the synopsis…" : "Scan the locked synopsis", systemImage: "magnifyingglass") }.disabled(scanning)
            } footer: { Text("One model call. (Prototype: fixed dummy results.)") }
            if scanned {
                Section {
                    Picker("State", selection: $tab) {
                        Text("Open \(count(0))").tag(0); Text("Created \(count(1))").tag(1); Text("Dismissed \(count(2))").tag(2)
                    }.pickerStyle(.segmented)
                }
                Section {
                    ForEach(items.filter { tabOf($0) == tab }) { it in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(it.name).font(.headline); Text("\(it.type.single) · \(it.note)").font(.caption).foregroundStyle(.secondary)
                            switch it.state {
                            case .open:
                                HStack { Button("Develop") { developing = it }.buttonStyle(.borderedProminent); Button("Link…") { linking = it }.buttonStyle(.bordered); Button("Dismiss") { set(it, .dismissed) }.buttonStyle(.bordered) }
                            case .created(let eid):
                                NavigationLink(value: Route.entry(eid)) { Text("Open the entry it became") }
                            case .dismissed:
                                Button("Put back") { set(it, .open) }.buttonStyle(.bordered)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Find missing").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $developing) { it in
            EditSheet(mode: .new(prefillName: it.name, type: it.type, onCreated: { set(it, .created($0)) }), onDone: {})
        }
        .sheet(item: $linking) { it in LinkPicker(item: it) { set(it, .created($0)) } }
    }
    private func tabOf(_ i: GapItem) -> Int { switch i.state { case .open: 0; case .created: 1; case .dismissed: 2 } }
    private func count(_ tab: Int) -> Int { items.filter { tabOf($0) == tab }.count }
    private func set(_ it: GapItem, _ s: GapItem.State) { if let i = items.firstIndex(where: { $0.id == it.id }) { items[i].state = s } }
    private func scan() { scanning = true; Task { try? await Task.sleep(for: .milliseconds(700)); items = DummyCodex.gaps(for: book, entries: store.entries); scanned = true; scanning = false } }
}

struct LinkPicker: View {
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: GapItem
    var chosen: (Int) -> Void
    @State private var q = ""
    var body: some View {
        NavigationStack {
            List {
                Section("“\(item.name)” is the same as…") {
                    ForEach(store.search(q.isEmpty ? String(item.name.split(separator: " ").last ?? "") : q, type: nil).prefix(30)) { h in
                        Button { chosen(h.id); dismiss() } label: { EntryRow(hit: h, showWhy: true) }.foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $q, prompt: "Search names and aliases")
            .navigationTitle("Link to existing").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: Ask Godric over the Codex

struct AskView: View {
    @Environment(CodexStore.self) private var store
    @State var question: String
    @State private var answer: [Entry]?
    init(initial: String) { _question = State(initialValue: initial) }
    var body: some View {
        List {
            Section { TextField("Ask about the Codex", text: $question, axis: .vertical); Button("Ask") { ask() }.disabled(question.isEmpty) }
            if let a = answer {
                Section("Answer") {
                    if a.isEmpty { Text("Nothing in the Codex matches that.") }
                    else {
                        Text("(Dummy answer.) " + a.enumerated().map { "\($0.element.name) is relevant [Entry \($0.offset + 1)]." }.joined(separator: " "))
                        FlowLayout { ForEach(Array(a.enumerated()), id: \.element.id) { i, e in
                            NavigationLink(value: Route.entry(e.id)) { Text("\(i + 1) \(e.name)").font(.footnote).padding(.horizontal, 10).padding(.vertical, 5).background(Color.accentColor.opacity(0.15), in: Capsule()) }
                        } }
                    }
                }
            }
        }
        .navigationTitle("Ask Godric").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !question.isEmpty, answer == nil { ask() } }
    }
    private func ask() {
        let words = question.split(separator: " ").map(String.init).filter { $0.count > 3 }
        var seen = Set<Int>(); var out: [Entry] = []
        for w in words { for h in store.search(w, type: nil) where !seen.contains(h.id) { seen.insert(h.id); out.append(h.entry) } }
        answer = Array(out.prefix(4))
    }
}
