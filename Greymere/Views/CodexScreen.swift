import SwiftUI
import UIKit

/// The Codex panel (ADR 0.59.0). Portrait: a drill-down (search and series, Recent, browse by type, then an entry).
/// Landscape, on both devices: the same menu on the left and the entry on the right, a draggable strip between
/// them, and a full-screen toggle. The shape was agreed on the simulator prototype (docs/codex-prototype-findings.md).
struct CodexScreen: View {
    @Bindable var model: CodexModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    /// Orientation read from a probe that ignores the keyboard. The keyboard shrinks the panel's own height, and a phone
    /// held upright with the keyboard up is then wider than it is tall: it flipped to the landscape layout, rebuilt the
    /// search field, and dropped its focus a moment after the tap.

    /// The window's own shape: it does not change when the keyboard comes up (the panel's does).
    private func windowLandscape(fallback: Bool) -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let b = scene?.keyWindow?.bounds ?? scene?.windows.first?.bounds else { return fallback }
        return b.width > b.height
    }

    var body: some View {
        VStack(spacing: 0) {
        GeometryReader { geo in
            let landscape = windowLandscape(fallback: geo.size.width > geo.size.height)
            ZStack(alignment: .top) {
                Group { if landscape { CodexLandscape(model: model, client: client) } else { CodexPhone(model: model, client: client) } }
                    .onAppear { model.landscape = landscape }
                    .onChange(of: landscape) { _, l in model.rotated(toLandscape: l) }
                if let text = model.banner {
                    Text(text).font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 4)
                        .onTapGesture { model.banner = nil }
                        .task(id: text) { try? await Task.sleep(for: .seconds(6)); if model.banner == text { model.banner = nil } }
                }
            }
        }
        }
        .background(connection.theme.background.ignoresSafeArea())
        .topBand(true, title: "Codex")
        .glassBar(isOpen: false) { model.banner = "Godric isn't on the Codex panel yet." }
        .task { await model.start(client: client) }
    }
}

enum CodexRoute: Hashable { case entry(Int), type(CodexType) }

// MARK: landscape

private struct CodexLandscape: View {
    @Bindable var model: CodexModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @State private var base: CGFloat?
    @State private var panelPath: [CodexRoute] = []

    var body: some View {
        GeometryReader { geo in
            let maxW = max(300, geo.size.width * 0.6)
            let w = min(max(model.leftWidth, 260), maxW)
            HStack(spacing: 0) {
                // The menu is never torn down: full screen only collapses its column and fades it, so its drill-down
                // position, scroll and search come back exactly as left, with nothing to rebuild.
                CodexPhone(model: model, client: client).frame(width: w, alignment: .leading)
                    .frame(width: model.fullScreen ? 0 : w, alignment: .leading)
                    .opacity(model.fullScreen ? 0 : 1)
                    .allowsHitTesting(!model.fullScreen)
                handle(maxW: maxW)
                Group {
                    if let id = model.selection, model.entry(id) != nil {
                        CodexStack(path: $panelPath, title: { r in if case .entry(let i) = r { return model.entry(i)?.name ?? "" } else { return "" } }) {
                            panelRoot(title: model.entry(id)?.name ?? "") { CodexEntryView(model: model, client: client, id: id) }
                        } page: { r in
                            if case .entry(let i) = r { CodexEntryView(model: model, client: client, id: i) }
                        }
                        .id(id)
                    } else {
                        panelRoot(title: "") {
                            ContentUnavailableView("Pick an entry", systemImage: "book.closed", description: Text("Search, or browse by type on the left."))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(connection.theme.background)
                .zIndex(1)
            }
        }
        .animation(.snappy, value: model.fullScreen)
        .onChange(of: model.selection) { _, _ in panelPath = [] }
    }

    /// The panel's top row is plain SwiftUI, not the UIKit nav bar: the nav bar re-applies the iPhone's side safe area
    /// a beat after the panel reaches the screen edge, which showed as a late jump to the left. Pushed screens (a chip
    /// opening another entry) still use the nav bar and its back button.
    private func panelRoot<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.headline).lineLimit(1).padding(.horizontal, 56)
                HStack {
                    Button { model.fullScreen.toggle() } label: {
                        Image(systemName: model.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.callout.weight(.medium)).foregroundStyle(connection.theme.text)
                            .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .accessibilityLabel(model.fullScreen ? "Show the menu" : "Full screen")
                    Spacer()
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Drag the strip to resize the menu column; a double tap toggles full screen.
    private func handle(maxW: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(connection.theme.faint.opacity(0.4)).frame(width: 0.5)
            Capsule().fill(connection.theme.faint).frame(width: 5, height: 44).opacity(model.fullScreen ? 0 : 1)
        }
        .frame(width: model.fullScreen ? 0 : 22).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard !model.fullScreen else { return }
                if base == nil { base = model.leftWidth }
                model.leftWidth = min(max((base ?? 360) + v.translation.width, 260), maxW)
            }
            .onEnded { _ in base = nil })
        .onTapGesture(count: 2) { model.fullScreen.toggle() }
    }
}


// MARK: a small stack of our own

private struct CodexPushKey: EnvironmentKey { static let defaultValue: @Sendable @MainActor (CodexRoute) -> Void = { _ in } }
private extension EnvironmentValues { var codexPush: @Sendable @MainActor (CodexRoute) -> Void { get { self[CodexPushKey.self] } set { self[CodexPushKey.self] = newValue } } }

/// The menu's and the panel's drill-down. It is plain SwiftUI, not UIKit's navigation controller: a controller with a
/// hidden bar lays its content out from the window's top (under the studio's band) and re-applies the iPhone's side
/// safe area a beat late, which showed as a jump. Here a page is a view and Back is a button.
private struct CodexStack<Root: View, Page: View>: View {
    @Binding var path: [CodexRoute]
    var title: (CodexRoute) -> String
    @ViewBuilder var root: () -> Root
    @ViewBuilder var page: (CodexRoute) -> Page
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        ZStack {
            if let last = path.last {
                VStack(spacing: 0) {
                    HStack {
                        Button { path.removeLast() } label: {
                            HStack(spacing: 4) { Image(systemName: "chevron.left").font(.body.weight(.semibold)); Text("Back") }
                                .frame(height: 44).contentShape(Rectangle())
                        }
                        Spacer()
                    }
                    .overlay { Text(title(last)).font(.headline).lineLimit(1).padding(.horizontal, 80) }
                    .padding(.horizontal, 16)
                    page(last).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(connection.theme.background)
                .transition(.move(edge: .trailing))
                .id(last)
            } else {
                root().transition(.opacity)
            }
        }
        .animation(.snappy, value: path)
        .environment(\.codexPush, { [path = $path] r in path.wrappedValue.append(r) })
        .clipShape(Rectangle())
    }
}

// MARK: glass rows

private struct CodexGlassRow: View {
    var selected = false
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.clear)
            .glassEffect(.regular.tint(selected ? connection.theme.accent.opacity(0.28) : connection.theme.glassTint), in: .rect(cornerRadius: 18))
            .padding(.vertical, 2)
    }
}

private extension View {
    func codexRow(selected: Bool = false) -> some View {
        self.listRowBackground(CodexGlassRow(selected: selected)).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// A row that opens an entry: pushes in portrait, selects into the right-hand panel in landscape.
private struct CodexLink<Label: View>: View {
    @Bindable var model: CodexModel
    let id: Int
    @ViewBuilder var label: () -> Label
    @Environment(\.codexPush) private var push
    var body: some View {
        if model.landscape {
            Button { model.selection = id; model.touch(id) } label: { HStack { label(); Spacer(minLength: 0) }.contentShape(Rectangle()) }
                .buttonStyle(.plain).codexRow(selected: model.selection == id)
        } else {
            Button { push(.entry(id)) } label: { HStack { label(); Spacer(minLength: 0); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }.contentShape(Rectangle()) }
                .buttonStyle(.plain).codexRow()
        }
    }
}

private struct CodexRow: View {
    @Bindable var model: CodexModel
    let hit: CodexHit
    var showWhy = false
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        let e = hit.entry
        HStack(spacing: 10) {
            Image(systemName: e.type.symbol).frame(width: 30, height: 30)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(connection.theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.body.weight(.semibold)).foregroundStyle(connection.theme.text).lineLimit(1)
                Text(subtitle(e)).font(.caption).foregroundStyle(connection.theme.muted).lineLimit(1)
                if showWhy {
                    switch hit.why {
                    case .alias(let a): Text("alias: \(a)").font(.caption.weight(.medium)).foregroundStyle(.green)
                    case .text: Text("text match").font(.caption).foregroundStyle(connection.theme.faint)
                    case .name: EmptyView()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func subtitle(_ e: CodexEntry) -> String {
        var s = e.type.single
        if e.parentId != nil, let b = model.building(of: e) { s += " · in \(b.name)" }
        else if e.type == .locations {
            let n = model.descendantCount(e.id)
            if n > 0 { s += " · \(n) inside" } else if let c = e.childCount, c > 0 { s += " · \(c) inside" }
        } else if !e.role.isEmpty { s += " · \(e.role)" }
        return s
    }
}

// MARK: the menu: home, search, type lists

private struct CodexPhone: View {
    @Bindable var model: CodexModel
    let client: APIClient

    var body: some View {
        CodexStack(path: $model.menuPath, title: { r in
            switch r { case .entry(let id): model.entry(id)?.name ?? ""; case .type(let t): t.title }
        }) {
            CodexHome(model: model, client: client, query: $model.query)
        } page: { r in
            switch r {
            case .entry(let id): CodexEntryView(model: model, client: client, id: id)
            case .type(let t): CodexTypeList(model: model, type: t)
            }
        }
        .onChange(of: model.menuPath) { _, p in if case .entry(let id)? = p.last { model.touch(id) } }
    }
}

private struct CodexHome: View {
    @Bindable var model: CodexModel
    let client: APIClient
    @Binding var query: String
    @Environment(\.codexPush) private var push
    @Environment(ConnectionModel.self) private var connection
    @State private var creating = false
    @FocusState private var searchFocused: Bool
    /// A phone on its side with the keyboard up has a few lines of height: the search row tightens so results show.
    private var compact: Bool { model.landscape && searchFocused }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CodexFilterMenu(model: model) { t in if let t { push(.type(t)) } }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(connection.theme.muted)
                    TextField("Search names, aliases, text", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(connection.theme.muted) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 14).frame(height: compact ? 34 : 44)
                .glassEffect(.regular.tint(connection.theme.glassTint), in: .capsule)
                .contentShape(Capsule()).onTapGesture { searchFocused = true }
            }
            .padding(.horizontal, 16).padding(.vertical, compact ? 2 : 6)

            List {
                if let error = model.loadError, model.entries.isEmpty {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }.codexRow()
                }
                if query.isEmpty {
                    Section {
                        Menu { CodexSeriesPicker(model: model) } label: {
                            HStack { Label(model.scopeName, systemImage: "books.vertical"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                .padding(.vertical, 6).contentShape(Rectangle())
                        }.codexRow()
                    }
                    let recent = model.recents.compactMap(model.entry)
                    if !recent.isEmpty {
                        Section("Recent") {
                            ForEach(recent, id: \.id) { e in CodexLink(model: model, id: e.id) { CodexRow(model: model, hit: CodexHit(entry: e, why: .name)) } }
                        }
                    }
                    Section {
                        Button { creating = true } label: { Label("New entry", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.plain).codexRow()
                    }
                    Section("Browse by type · \(model.count(nil)) in scope") {
                        ForEach(CodexType.allCases) { t in
                            Button { push(.type(t)) } label: {
                                HStack { Label(t.title, systemImage: t.symbol); Spacer(); Text("\(model.count(t))").foregroundStyle(connection.theme.muted); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).codexRow()
                        }
                    }
                } else {
                    let hits = model.search(query, type: nil)
                    Section("\(hits.count) results") {
                        ForEach(hits) { h in CodexLink(model: model, id: h.id) { CodexRow(model: model, hit: h, showWhy: true) } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $creating) {
                CodexEditSheet(model: model, client: client, id: nil) { newId in
                    model.touch(newId)
                    if model.landscape { model.selection = newId } else { push(.entry(newId)) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay { if model.loading && model.entries.isEmpty { ProgressView() } }
            .refreshable { await model.reload() }
        }
    }
}

private struct CodexSeriesPicker: View {
    @Bindable var model: CodexModel
    var body: some View {
        Picker("Series", selection: Binding(get: { model.seriesId ?? 0 }, set: { model.chooseSeries($0 == 0 ? nil : $0) })) {
            Text("All series").tag(0)
            ForEach(model.series) { Text($0.name).tag($0.id) }
        }
    }
}

/// One pull-down for everything that is not content: the type shortcut, the series, and the fold switch. It sits
/// top left: the top right belongs to the app's Settings gear.
private struct CodexFilterMenu: View {
    @Bindable var model: CodexModel
    var onType: (CodexType?) -> Void
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        Menu {
            Section("Show") {
                ForEach(CodexType.allCases) { t in
                    Button { onType(t) } label: { Label("\(t.title) (\(model.count(t)))", systemImage: t.symbol) }
                }
            }
            Section("Series") { CodexSeriesPicker(model: model) }
            Toggle("Show contained places", isOn: $model.showContained)
        } label: {
            Image(systemName: "line.3.horizontal.decrease").font(.body.weight(.semibold)).foregroundStyle(connection.theme.text)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .glassEffect(.regular.tint(connection.theme.glassTint).interactive(), in: .circle)
        .accessibilityLabel("Filter")
    }
}

private struct CodexTypeList: View {
    @Bindable var model: CodexModel
    let type: CodexType
    @State private var query = ""
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        let hits = model.list(type: type, query: query)
        List {
            if type == .locations {
                Section {
                    Toggle("Show contained places", isOn: $model.showContained)
                    let contained = model.entries.filter { $0.type == .locations && $0.parentId != nil }.count
                    if !model.showContained && contained > 0 {
                        Text("\(contained) rooms and floors are inside their building. Switch on to list them.").font(.footnote).foregroundStyle(connection.theme.muted)
                    }
                }
            }
            ForEach(hits) { h in CodexLink(model: model, id: h.id) { CodexRow(model: model, hit: h, showWhy: !query.isEmpty) } }
        }
        .scrollContentBackground(.hidden)
        .background(connection.theme.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(connection.theme.muted)
                TextField("Filter \(type.title.lowercased())", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(height: 40)
            .glassEffect(.regular.tint(connection.theme.glassTint), in: .capsule)
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

// MARK: the entry (read-only in this slice)

private struct CodexFlow: Layout {
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

private struct CodexEntryView: View {
    @Bindable var model: CodexModel
    let client: APIClient
    let id: Int
    @State private var showAllChildren = false
    @State private var editing = false
    @State private var confirmDelete = false
    @Environment(\.codexPush) private var push
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        if let e = model.entry(id) {
            let detail = model.details[id]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        portrait(detail?.portraitPath ?? e.portraitPath, type: e.type)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(e.name).font(.serif(26)).foregroundStyle(connection.theme.text)
                                Spacer(minLength: 8)
                                Button { editing = true } label: {
                                    Label("Edit", systemImage: "pencil").font(.footnote.weight(.medium)).foregroundStyle(connection.theme.accent)
                                        .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.interactive(), in: .capsule)
                                }
                                .buttonStyle(.plain).disabled(detail == nil)
                            }
                            Text("\(e.type.single) · \(model.scopeName)").font(.subheadline).foregroundStyle(connection.theme.muted)
                            let aliases = detail?.aliases ?? e.allAliases
                            if !aliases.isEmpty { Text("Also known as: " + aliases.joined(separator: ", ")).font(.footnote).foregroundStyle(connection.theme.text) }
                            let books = (detail?.appearancesByBook ?? []).compactMap(\.bookTitle)
                            if !books.isEmpty, e.type == .characters || e.type == .locations { Text("Appears in: " + books.joined(separator: ", ")).font(.footnote).foregroundStyle(connection.theme.muted) }
                            if let u = detail?.updatedAt ?? e.updatedAt { Text("Edited \(u)").font(.caption).foregroundStyle(connection.theme.faint) }
                        }
                    }
                    let trail = model.ancestors(of: e)
                    if !trail.isEmpty {
                        CodexFlow { ForEach(trail) { a in Button { push(.entry(a.id)) } label: { chip("In: \(a.name)", systemImage: "arrow.up.left") }.buttonStyle(.plain) } }
                    }
                    let kids = model.children(of: e.id)
                    if !kids.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Contains · \(model.descendantCount(e.id))").font(.footnote).foregroundStyle(connection.theme.muted)
                            CodexFlow {
                                ForEach(showAllChildren ? kids : Array(kids.prefix(6))) { k in
                                    let n = model.descendantCount(k.id)
                                    Button { push(.entry(k.id)) } label: { chip(n > 0 ? "\(k.name) (\(n))" : k.name, accent: true) }.buttonStyle(.plain)
                                }
                                if !showAllChildren, kids.count > 6 { Button { showAllChildren = true } label: { chip("+\(kids.count - 6) more", accent: true) } }
                            }
                        }
                    }
                    CodexBody(text: detail?.body ?? e.snippet)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete entry", systemImage: "trash").font(.footnote.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8).glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain).foregroundStyle(.red).padding(.top, 12)
                }
                .padding()
            }
            .background(connection.theme.background)
            .task(id: id) { await model.loadDetail(id) }
            .confirmationDialog("Delete \(e.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete for good", role: .destructive) { Task { _ = await model.delete(id, client: client) } }
                Button("Keep it", role: .cancel) {}
            } message: { Text("Its aliases and image go with it, and any Find missing item it filled reopens. This can't be undone.") }
            .sheet(isPresented: $editing) { CodexEditSheet(model: model, client: client, id: id) }
        } else {
            ContentUnavailableView("Entry not found", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder private func portrait(_ path: String?, type: CodexType) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        if let url = client.asset(path) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { shape.fill(Color(.secondarySystemFill)).overlay { Image(systemName: type.symbol).foregroundStyle(connection.theme.muted) } }
            }
            .frame(width: 84, height: 108).clipShape(shape)
        } else {
            shape.fill(Color(.secondarySystemFill)).frame(width: 84, height: 108)
                .overlay { VStack { Image(systemName: type.symbol).font(.title2); Text("no image").font(.caption2) }.foregroundStyle(connection.theme.muted) }
        }
    }

    private func chip(_ t: String, systemImage: String? = nil, accent: Bool = false) -> some View {
        HStack(spacing: 4) { if let systemImage { Image(systemName: systemImage) }; Text(t) }
            .font(.footnote).padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(accent ? connection.theme.accent : connection.theme.text)
            .glassEffect(.regular.tint(accent ? connection.theme.accent.opacity(0.18) : connection.theme.glassTint).interactive(), in: .capsule)
    }
}

/// The entry's Markdown body: headings, bullets and paragraphs, with bold and italic inside them.
private struct CodexBody: View {
    let text: String
    @Environment(ConnectionModel.self) private var connection

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { Color.clear.frame(height: 2) }
                else if line.hasPrefix("#") {
                    inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)).font(.headline).padding(.top, 6)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); inline(String(line.dropFirst(2))) }
                } else { inline(line) }
            }
        }
        .font(.body).foregroundStyle(connection.theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


