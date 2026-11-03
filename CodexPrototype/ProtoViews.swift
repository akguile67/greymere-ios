// THROWAWAY prototype views (ADR 0.59.0 Sprint 1): navigation only.
import SwiftUI

@main
struct CodexProtoApp: App {
    @State private var store = CodexStore()
    var body: some Scene {
        WindowGroup { ProtoShell().environment(store) }
    }
}

enum Route: Hashable { case entry(Int), type(EType), findMissing, ask(String) }

struct CodexRoot: View {
    @Environment(CodexStore.self) private var store
    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            let pad = UIDevice.current.userInterfaceIdiom == .pad
            if pad && !(portrait && store.ipadPortraitDrill) { SplitLayout().onAppear { store.split = true } }
            else { PhoneLayout().onAppear { store.split = false } }
        }
    }
}

// MARK: iPad — list left, entry right (landscape and portrait)

struct SplitLayout: View {
    @Environment(CodexStore.self) private var store
    @State private var selection: Int?
    @State private var query = ""
    @State private var type: EType?
    @State private var sheet: ToolSheet?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            EntryList(query: $query, type: $type, selection: $selection)
                .navigationTitle("Codex")
                .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 380)
                .searchable(text: $query, prompt: "Search names, aliases, text")
                .toolbar { CodexMenu(sheet: $sheet) }
        } detail: {
            if let id = selection {
                NavigationStack {
                    EntryView(id: id)
                        .navigationDestination(for: Route.self) { r in if case .entry(let i) = r { EntryView(id: i) } }
                }
                .id(id)
            } else {
                ContentUnavailableView("Pick an entry", systemImage: "book.closed", description: Text("Search by name or alias, or browse by type."))
            }
        }
        .sheet(item: $sheet) { ToolSheetView(kind: $0, open: { selection = $0 }) }
    }
}

enum ToolSheet: String, Identifiable { case find, ask, newEntry; var id: String { rawValue } }

struct ToolSheetView: View {
    let kind: ToolSheet
    var open: (Int) -> Void
    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .find: FindMissingView()
                case .ask: AskView(initial: "")
                case .newEntry: EditSheet(mode: .new(prefillName: "", type: .character, onCreated: { open($0) }), onDone: {})
                }
            }
            .navigationDestination(for: Route.self) { r in if case .entry(let i) = r { EntryView(id: i) } }
        }
    }
}

struct CodexMenu: ToolbarContent {
    @Environment(CodexStore.self) private var store
    @Binding var sheet: ToolSheet?
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { sheet = .newEntry } label: { Image(systemName: "plus") }
            Menu {
                ScopeMenu()
                @Bindable var s = store
                Toggle("Show contained places", isOn: $s.showContained)
                Divider()
                Button { sheet = .find } label: { Label("Find missing", systemImage: "magnifyingglass") }
                Button { sheet = .ask } label: { Label("Ask Godric", systemImage: "bubble.left.and.text.bubble.right") }
                Divider()
                Toggle("Prototype: iPad portrait drill-down", isOn: $s.ipadPortraitDrill)
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

struct ScopeMenu: View {
    @Environment(CodexStore.self) private var store
    var body: some View {
        Picker("Series", selection: Binding(get: { store.scope ?? "All series" }, set: { store.scope = $0 == "All series" ? nil : $0 })) {
            Text("All series").tag("All series")
            ForEach(DummyCodex.series, id: \.name) { Text($0.name).tag($0.name) }
        }
    }
}

/// The iPad list column: chip strip, then recents, then rows. Rows select; the detail pane follows.
struct EntryList: View {
    @Environment(CodexStore.self) private var store
    @Binding var query: String
    @Binding var type: EType?
    @Binding var selection: Int?

    var body: some View {
        let hits = store.list(type: type, query: query)
        List(selection: $selection) {
            if query.isEmpty, type == nil, !store.recents.isEmpty {
                Section("Recent") {
                    ForEach(store.recents.compactMap(store.entry), id: \.id) { EntryRow(hit: Hit(entry: $0, why: .name)).tag($0.id) }
                }
            }
            Section(type?.title ?? "All entries") {
                ForEach(hits) { EntryRow(hit: $0, showWhy: !query.isEmpty).tag($0.id) }
            }
            if type == .location || type == nil, !store.showContained, query.isEmpty {
                Text("\(store.inScope.filter { $0.type == .location && $0.parent != nil }.count) rooms and floors are inside their building. Switch on \"Show contained places\" in ⋯ to list them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { TypeChips(type: $type, query: query).padding(.horizontal).padding(.vertical, 6).background(.bar) }
        .onChange(of: selection) { _, new in if let new { store.touch(new) } }
    }
}

struct TypeChips: View {
    @Environment(CodexStore.self) private var store
    @Binding var type: EType?
    var query: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", nil)
                ForEach(EType.allCases) { chip($0.title, $0) }
            }
        }
    }
    private func n(_ t: EType?) -> Int { query.isEmpty ? store.count(t) : store.search(query, type: t).count }
    private func chip(_ title: String, _ t: EType?) -> some View {
        Button { type = t } label: {
            Text("\(title) \(n(t))").font(.footnote).padding(.horizontal, 10).padding(.vertical, 5)
                .background(type == t ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(type == t ? Color.white : Color.primary)
        }.buttonStyle(.plain)
    }
}

struct EntryRow: View {
    @Environment(CodexStore.self) private var store
    let hit: Hit
    var showWhy = false
    var body: some View {
        let e = hit.entry
        HStack(spacing: 10) {
            Image(systemName: e.type.symbol).frame(width: 30, height: 30)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(subtitle(e)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if showWhy { switch hit.why { case .alias(let a): Text("alias: \(a)").font(.caption.weight(.medium)).foregroundStyle(.green); case .text: Text("text match").font(.caption).foregroundStyle(.tertiary); case .name: EmptyView() } }
            }
            Spacer(minLength: 0)
        }
    }
    private func subtitle(_ e: Entry) -> String {
        var s = e.type.single
        if let b = store.building(of: e), e.parent != nil { s += " · in \(b.name)" }
        else if e.type == .location { let n = store.descendantCount(e.id); if n > 0 { s += " · \(n) inside" } }
        else if !e.role.isEmpty { s += " · \(e.role)" }
        return s
    }
}

// MARK: iPhone — home, drill-down stack

struct PhoneLayout: View {
    @Environment(CodexStore.self) private var store
    @State private var path: [Route] = []
    @State private var query = ""
    @State private var sheet: ToolSheet?

    var body: some View {
        NavigationStack(path: $path) {
            PhoneHome(query: $query, path: $path)
                .navigationTitle("Codex")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search names, aliases, text")
                .toolbar { CodexMenu(sheet: $sheet) }
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .entry(let id): EntryView(id: id)
                    case .type(let t): PhoneTypeList(type: t)
                    case .findMissing: FindMissingView()
                    case .ask(let q): AskView(initial: q)
                    }
                }
        }
        .sheet(item: $sheet) { ToolSheetView(kind: $0, open: { path.append(.entry($0)) }) }
    }
}

struct PhoneHome: View {
    @Environment(CodexStore.self) private var store
    @Binding var query: String
    @Binding var path: [Route]
    @State private var chip: EType?

    var body: some View {
        List {
            if query.isEmpty {
                if let g = store.godricContext.flatMap(store.entry) {
                    Label("Godric is looking at \(g.name)", systemImage: "eye").font(.footnote)
                        .swipeActions { Button("Clear") { store.godricContext = nil } }
                }
                Section {
                    Menu { ScopeMenu() } label: { HStack { Label(store.scope ?? "All series", systemImage: "books.vertical"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) } }
                }
                Section("Recent") {
                    ForEach(store.recents.compactMap(store.entry), id: \.id) { e in
                        NavigationLink(value: Route.entry(e.id)) { EntryRow(hit: Hit(entry: e, why: .name)) }
                    }
                }
                Section("Browse by type · \(store.count(nil)) in scope") {
                    ForEach(EType.allCases) { t in
                        NavigationLink(value: Route.type(t)) { HStack { Label(t.title, systemImage: t.symbol); Spacer(); Text("\(store.count(t))").foregroundStyle(.secondary) } }
                    }
                }
                Section("Tools") {
                    NavigationLink(value: Route.findMissing) { Label("Find missing", systemImage: "magnifyingglass") }
                    NavigationLink(value: Route.ask("")) { Label("Ask Godric about the Codex", systemImage: "bubble.left.and.text.bubble.right") }
                }
            } else {
                let hits = store.search(query, type: chip)
                Section {
                    TypeChips(type: $chip, query: query).listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                Section("\(hits.count) results") {
                    ForEach(hits) { h in NavigationLink(value: Route.entry(h.id)) { EntryRow(hit: h, showWhy: true) } }
                }
                Section { NavigationLink(value: Route.ask(query)) { Label("Ask Godric: “\(query)”", systemImage: "bubble.left.and.text.bubble.right") } }
            }
        }
        .onChange(of: path) { _, p in if case .entry(let id)? = p.last { store.touch(id) } }
    }
}

struct PhoneTypeList: View {
    @Environment(CodexStore.self) private var store
    let type: EType
    @State private var query = ""
    var body: some View {
        @Bindable var s = store
        let hits = store.list(type: type, query: query)
        List {
            if type == .location {
                Section {
                    Toggle("Show contained places", isOn: $s.showContained)
                    if !store.showContained {
                        Text("\(store.inScope.filter { $0.type == .location && $0.parent != nil }.count) rooms and floors are inside their building. Switch on to list them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(hits) { h in NavigationLink(value: Route.entry(h.id)) { EntryRow(hit: h, showWhy: !query.isEmpty) } }
        }
        .navigationTitle(type.title)
        .searchable(text: $query, prompt: "Filter \(type.title.lowercased())")
    }
}

// MARK: The entry (shared by iPad detail and iPhone stack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

struct EntryView: View {
    enum Sheet: Identifiable { case edit(dictate: Bool), image, books, standardise; var id: String { switch self { case .edit(let d): "edit\(d)"; case .image: "i"; case .books: "b"; case .standardise: "s" } } }
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @State private var showAllChildren = false

    var body: some View {
        if let e = store.entry(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)).frame(width: 84, height: 108)
                            .overlay { VStack { Image(systemName: e.image == .none ? e.type.symbol : "photo").font(.title2); Text(e.image == .none ? "no image" : e.image == .pending ? "pending review" : "approved").font(.caption2) }.foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.name).font(.title2.weight(.semibold))
                            Text("\(e.type.single) · \(e.series.joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
                            if !e.aliases.isEmpty { Text("Also known as: " + e.aliases.joined(separator: ", ")).font(.footnote) }
                            if (e.type == .character || e.type == .location), !e.books.isEmpty { Text("Appears in: " + e.books.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary) }
                            Text("Edited \(e.edited) · v\(e.version)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    let trail = store.ancestors(of: e)
                    if !trail.isEmpty {
                        FlowLayout { ForEach(trail) { a in NavigationLink(value: Route.entry(a.id)) { chip("In: \(a.name)", systemImage: "arrow.up.left") } } }
                    }
                    let kids = store.children(of: e.id)
                    if !kids.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Contains · \(store.descendantCount(e.id))").font(.footnote).foregroundStyle(.secondary)
                            FlowLayout {
                                ForEach(showAllChildren ? kids : Array(kids.prefix(6))) { k in
                                    let n = store.descendantCount(k.id)
                                    NavigationLink(value: Route.entry(k.id)) { chip(n > 0 ? "\(k.name) (\(n))" : k.name, accent: true) }
                                }
                                if !showAllChildren, kids.count > 6 { Button { showAllChildren = true } label: { chip("+\(kids.count - 6) more", accent: true) } }
                            }
                        }
                    }
                    Text((try? AttributedString(markdown: e.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(e.body))
                        .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle(e.name).navigationBarTitleDisplayMode(.inline)
            .onAppear { store.currentEntry = id; store.godricContext = id }
            .onDisappear { if store.currentEntry == id { store.currentEntry = nil; store.godricContext = nil } }
            .onChange(of: store.editToken) { _, _ in if store.currentEntry == id { sheet = .edit(dictate: false) } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { sheet = .edit(dictate: false) } label: { Label("Edit", systemImage: "pencil") }
                        Button { sheet = .edit(dictate: true) } label: { Label("Dictate an edit", systemImage: "mic") }
                        if e.type == .location { Button { sheet = .standardise } label: { Label("Standardise to template", systemImage: "wand.and.stars") } }
                        Button { sheet = .image } label: { Label("Image…", systemImage: "photo") }
                        Button { sheet = .books } label: { Label("Series, books, scope…", systemImage: "books.vertical") }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete entry", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Delete \(e.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { store.delete(id); dismiss() }
            } message: { Text("This also deletes anything inside it and reopens a linked Find missing item.") }
            .sheet(item: $sheet) { s in
                switch s {
                case .edit(let d): EditSheet(mode: .edit(id, dictate: d), onDone: { sheet = nil })
                case .image: ImageSheet(id: id)
                case .books: BooksSheet(id: id)
                case .standardise: StandardiseSheet(id: id, onDone: { sheet = nil })
                }
            }
        } else {
            ContentUnavailableView("Entry deleted", systemImage: "trash")
        }
    }

    private func chip(_ t: String, systemImage: String? = nil, accent: Bool = false) -> some View {
        HStack(spacing: 4) { if let systemImage { Image(systemName: systemImage) }; Text(t) }
            .font(.footnote).padding(.horizontal, 10).padding(.vertical, 5)
            .background(accent ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
    }
}
