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
            let landscape = geo.size.width > geo.size.height
            Group {
                if landscape { LandscapeLayout() } else { PhoneLayout() }
            }
            .onAppear { store.landscape = landscape }
            .onChange(of: landscape) { _, l in store.landscape = l }
        }
    }
}

/// Landscape (iPad and iPhone): the same menu as portrait stays on the left, the working panel (the entry) on the right.
struct LandscapeLayout: View {
    @Environment(CodexStore.self) private var store
    @State private var base: CGFloat?
    var body: some View {
        GeometryReader { geo in
            let maxW = max(300, geo.size.width * 0.6)
            let w = min(max(store.leftWidth, 260), maxW)
            HStack(spacing: 0) {
                // The menu is never torn down: full screen only collapses its column and fades it, so its drill-down
                // position, scroll and search come back exactly as left, with nothing to rebuild.
                PhoneLayout().frame(width: w, alignment: .leading)
                    .frame(width: store.fullScreen ? 0 : w, alignment: .leading)
                    .opacity(store.fullScreen ? 0 : 1)
                    .allowsHitTesting(!store.fullScreen)
                handle(maxW: maxW)
                Group {
                    if let id = store.selection, store.entry(id) != nil {
                        NavigationStack {
                            EntryView(id: id)
                                .toolbar { fullScreenItem }
                                .navigationDestination(for: Route.self) { r in if case .entry(let i) = r { EntryView(id: i) } }
                        }
                        .id(id)
                    } else {
                        NavigationStack {
                            ContentUnavailableView("Pick an entry", systemImage: "book.closed", description: Text("Search, or browse by type on the left."))
                                .toolbar { fullScreenItem }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .zIndex(1)
            }
        }
        .animation(.snappy, value: store.fullScreen)
    }

    /// Inline in the panel's top bar, left-aligned with the entry picture; same size as the search icon.
    @ToolbarContentBuilder private var fullScreenItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { store.fullScreen.toggle() } label: {
                Image(systemName: store.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.callout.weight(.medium)).foregroundStyle(.primary).offset(x: -5)
            }
            .accessibilityLabel(store.fullScreen ? "Show the menu" : "Full screen")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// Drag the strip to resize the left column; double tap toggles full screen.
    private func handle(maxW: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color(.separator)).frame(width: 0.5)
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 5, height: 44)
                .opacity(store.fullScreen ? 0 : 1)
        }
        .frame(width: store.fullScreen ? 0 : 22).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard !store.fullScreen else { return }
                if base == nil { base = store.leftWidth }
                store.leftWidth = min(max((base ?? 360) + v.translation.width, 260), maxW)
            }
            .onEnded { _ in base = nil })
        .onTapGesture(count: 2) { store.fullScreen.toggle() }
    }
}

/// Liquid-glass background for list rows (and a tint when selected).
struct GlassRow: View {
    var selected = false
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.clear)
            .glassEffect(.regular.tint(selected ? Color.accentColor.opacity(0.28) : Color(.systemGray).opacity(0.16)), in: .rect(cornerRadius: 18))
            .padding(.vertical, 2)
    }
}
extension View {
    func glassRows(selected: Bool = false) -> some View {
        self.listRowBackground(GlassRow(selected: selected)).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// A row that opens an entry: pushes in portrait, selects into the right-hand panel in landscape.
struct EntryLink<Label: View>: View {
    @Environment(CodexStore.self) private var store
    let id: Int
    @ViewBuilder var label: () -> Label
    var body: some View {
        if store.landscape {
            Button { store.selection = id; store.touch(id) } label: { HStack { label(); Spacer(minLength: 0) } .contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .glassRows(selected: store.selection == id)
        } else {
            NavigationLink(value: Route.entry(id), label: label).glassRows()
        }
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

/// The entry's actions: in the glass bar's ⋯ and in the top-left menu while an entry is open.
struct EntryActionButtons: View {
    @Environment(CodexStore.self) private var store
    var body: some View {
        if let id = store.currentEntry, let e = store.entry(id) {
            Button { store.pendingAction = .edit } label: { Label("Edit", systemImage: "pencil") }
            Button { store.pendingAction = .dictate } label: { Label("Dictate an edit", systemImage: "mic") }
            if e.type == .location { Button { store.pendingAction = .standardise } label: { Label("Standardise to template", systemImage: "wand.and.stars") } }
            Button { store.pendingAction = .image } label: { Label("Image…", systemImage: "photo") }
            Button { store.pendingAction = .books } label: { Label("Series, books, scope…", systemImage: "books.vertical") }
            Button(role: .destructive) { store.pendingAction = .delete } label: { Label("Delete entry", systemImage: "trash") }
        }
    }
}

/// One pull-down for everything that is not content: the type filter, series scope, the fold switch and the tools.
/// It sits top LEFT: the top right belongs to the app's Settings gear. "New" lives in the glass bar.
struct FilterMenu: View {
    @Environment(CodexStore.self) private var store
    @Binding var sheet: ToolSheet?
    var current: EType?
    var onType: (EType?) -> Void
    var body: some View {
        @Bindable var s = store
        Menu {
            if store.currentEntry != nil { Section("This entry") { EntryActionButtons() } }
            Section("Show") {
                Button { onType(nil) } label: { Label("All (\(store.count(nil)))", systemImage: current == nil ? "checkmark" : "square.grid.2x2") }
                ForEach(EType.allCases) { t in
                    Button { onType(t) } label: { Label("\(t.title) (\(store.count(t)))", systemImage: current == t ? "checkmark" : t.symbol) }
                }
            }
            Section("Series") { ScopeMenu() }
            Toggle("Show contained places", isOn: $s.showContained)
            Section {
                Button { sheet = .find } label: { Label("Find missing", systemImage: "magnifyingglass") }
                Button { sheet = .ask } label: { Label("Ask Godric about the Codex", systemImage: "bubble.left.and.text.bubble.right") }
            }
        } label: { Image(systemName: current == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
        .accessibilityLabel("Filter and tools")
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
            PhoneHome(query: $query, path: $path, sheet: $sheet)
                .navigationTitle("Codex")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search names, aliases, text")
                .onChange(of: store.newToken) { _, _ in sheet = .newEntry }
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .entry(let id): EntryView(id: id)
                    case .type(let t): PhoneTypeList(type: t)
                    case .findMissing: FindMissingView()
                    case .ask(let q): AskView(initial: q)
                    }
                }
        }
        .sheet(item: $sheet) { ToolSheetView(kind: $0, open: { if store.landscape { store.selection = $0 } else { path.append(.entry($0)) } }) }
    }
}

struct PhoneHome: View {
    @Environment(CodexStore.self) private var store
    @Binding var query: String
    @Binding var path: [Route]
    @Binding var sheet: ToolSheet?
    @State private var chip: EType?

    var body: some View {
        List {
            if query.isEmpty {
                if let g = store.godricContext.flatMap(store.entry) {
                    Label("Godric is looking at \(g.name)", systemImage: "eye").font(.footnote)
                        .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                        .glassRows()
                }
                Section {
                    Menu { ScopeMenu() } label: {
                        HStack { Label(store.scope ?? "All series", systemImage: "books.vertical"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                            .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .glassRows()
                }
                Section("Recent") {
                    ForEach(store.recents.compactMap(store.entry), id: \.id) { e in
                        EntryLink(id: e.id) { EntryRow(hit: Hit(entry: e, why: .name)) }
                    }
                }
                Section("Browse by type · \(store.count(nil)) in scope") {
                    ForEach(EType.allCases) { t in
                        NavigationLink(value: Route.type(t)) { HStack { Label(t.title, systemImage: t.symbol); Spacer(); Text("\(store.count(t))").foregroundStyle(.secondary) } }.glassRows()
                    }
                }
            } else {
                let hits = store.search(query, type: chip)
                Section("\(hits.count) results" + (chip.map { " in \($0.title)" } ?? "")) {
                    ForEach(hits) { h in EntryLink(id: h.id) { EntryRow(hit: h, showWhy: true) } }
                }
                Section { NavigationLink(value: Route.ask(query)) { Label("Ask Godric: “\(query)”", systemImage: "bubble.left.and.text.bubble.right") }.glassRows() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                FilterMenu(sheet: $sheet, current: query.isEmpty ? nil : chip) { t in
                    if query.isEmpty { if let t { path.append(.type(t)) } } else { chip = t }
                }
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
            ForEach(hits) { h in EntryLink(id: h.id) { EntryRow(hit: h, showWhy: !query.isEmpty) } }
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
            .onChange(of: store.pendingAction) { _, a in
                guard store.currentEntry == id, let a else { return }
                store.pendingAction = nil
                switch a {
                case .edit: sheet = .edit(dictate: false)
                case .dictate: sheet = .edit(dictate: true)
                case .standardise: sheet = .standardise
                case .image: sheet = .image
                case .books: sheet = .books
                case .delete: confirmDelete = true
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
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
            .glassEffect(.regular.tint(accent ? Color.accentColor.opacity(0.18) : Color(.systemGray).opacity(0.16)).interactive(), in: .capsule)
    }
}
