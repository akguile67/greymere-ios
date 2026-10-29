import SwiftUI

/// Home: the status cards, the shelf and Today. Book Details opens beside Home only when the screen is wide
/// enough for both (iPad on its side, a large iPad); otherwise it is a screen of its own with a back button,
/// as on the iPhone and an iPad mini held upright.
struct HomeScreen: View {
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @State private var home = HomeModel()
    @State private var selected: String?
    @AppStorage("greymere.detailFraction") private var detailFraction: Double = 0.46
    @State private var dragStart: Double?
    @State private var expanded = false
    @State private var godric = GodricModel()
    @State private var chatOpen = false
    @State private var chatBook: ChatBook?

    /// Width needed to show Home and Book Details side by side.
    private static let splitMinimum: CGFloat = 900

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= Self.splitMinimum { split(total: geo.size.width) } else { stack }
            }
        }
        .task { await home.load(using: client) }
    }

    private func split(total: CGFloat) -> some View {
        let detailWidth = min(max(total * detailFraction, 340), total - 380)
        let chosen = home.item(selected)
        let showsRight = chatOpen || chosen?.opensPanel == true
        return Group {
            if expanded, !chatOpen, let item = chosen, item.opensPanel {
                // The details take the whole screen; the arrows bring Home back.
                panel(item, showsBar: true, isExpanded: true, onToggleExpand: { expanded = false },
                      onClose: { selected = nil; expanded = false })
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    // Home is given exactly what the details leave; left to itself it will not shrink below its widest row.
                    HomeContent(home: home, client: client, selected: $selected, showsBar: true, onGodric: toggleChat, chatIsOpen: chatOpen)
                        .frame(width: showsRight ? total - detailWidth - 18 : total)
                        .clipped()
                    if showsRight {
                        handle(total: total, current: detailWidth)
                        Group {
                            if chatOpen {
                                GodricChatView(model: godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                            } else if let item = chosen {
                                panel(item, showsBar: false, isExpanded: false, onToggleExpand: { expanded = true },
                                      onClose: { selected = nil })
                            }
                        }
                        .frame(width: detailWidth)
                        .layoutPriority(1)
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .animation(.snappy, value: selected)
        .animation(.snappy, value: expanded)
        .animation(.snappy, value: chatOpen)
        .onChange(of: selected) { _, new in if new != nil { chatOpen = false } }
    }

    /// Opening Godric closes any details beside Home (the screen has room for one side panel).
    private func toggleChat() {
        withAnimation(.snappy) {
            chatBook = nil
            chatOpen.toggle()
            if chatOpen { selected = nil; expanded = false }
        }
    }

    /// Book Details for a book, the seed screen for a seed.
    @ViewBuilder
    private func panel(_ item: ShelfItem, showsBar: Bool, isExpanded: Bool,
                       onToggleExpand: (() -> Void)?, onClose: (() -> Void)?) -> some View {
        if item.isSeed {
            SeedDetailView(item: item, client: client, showsBar: showsBar, isExpanded: isExpanded,
                           onToggleExpand: onToggleExpand, onClose: onClose)
        } else if let detail = item.detail {
            BookDetailView(item: item, figures: detail, client: client, showsBar: showsBar,
                           isExpanded: isExpanded, onToggleExpand: onToggleExpand, onClose: onClose)
                .godricButton(isOpen: false) { openChat(about: item) }
        }
    }

    /// Chat opened from a book: the same Home thread, with that book in focus.
    private func openChat(about item: ShelfItem) {
        withAnimation(.snappy) {
            chatBook = ChatBook(id: item.rawId, title: item.title)
            selected = nil; expanded = false
            chatOpen = true
        }
    }

    /// Drag to give Home or the details more room; the width is remembered.
    private func handle(total: CGFloat, current: CGFloat) -> some View {
        Rectangle().fill(.clear).frame(width: 18)
            .overlay(Capsule().fill(connection.theme.faint.opacity(0.6)).frame(width: 4, height: 44))
            .overlay(alignment: .center) { Divider() }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        let start = dragStart ?? current
                        dragStart = start
                        let w = min(max(start - v.translation.width, 340), total - 380)
                        detailFraction = Double(w / total)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityLabel("Resize")
    }

    private var stack: some View {
        NavigationStack {
            HomeContent(home: home, client: client, selected: $selected, showsBar: true, onGodric: toggleChat)
                .navigationDestination(isPresented: $chatOpen) {
                    GodricChatView(model: godric, client: client, showsBar: true, book: chatBook, onClose: { chatOpen = false })
                }
                .navigationDestination(item: $selected) { id in
                    if let item = home.item(id), item.opensPanel {
                        panel(item, showsBar: true, isExpanded: false, onToggleExpand: nil, onClose: nil)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ShelfGroup: Identifiable {
    let id: String
    let title: String
    let items: [ShelfItem]
}

private struct HomeContent: View {
    let home: HomeModel
    let client: APIClient
    @Binding var selected: String?
    var showsBar = true
    var onGodric: (() -> Void)?
    var chatIsOpen = false
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var width: CGFloat = 0
    @State private var cardOrder = OrderStore(key: "cards")
    @State private var groupOrder = OrderStore(key: "shelfGroups")
    @State private var targetedGroup: String?
    @AppStorage("greymere.collapsedGroups") private var collapsedRaw = ""
    @State private var today = TodayModel()

    private var cardWidth: CGFloat { sizeClass == .regular ? 124 : 96 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = home.summary {
                    cards(cardOrder.sorted(summary.cards))
                    shelf
                    TodayCard(model: today, client: client, collapsed: isCollapsed("today"), onToggle: { withAnimation(.snappy) { toggleCollapsed("today") } })
                } else if home.failed {
                    Text("Home couldn't be loaded. Pull down to try again.").foregroundStyle(connection.theme.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .environmentBar(showsBar)
        .godricButton(isOpen: chatIsOpen) { onGodric?() }
        .background(connection.theme.background.ignoresSafeArea())
        .refreshable { await home.load(using: client); await today.load(client: client) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await home.load(using: client); await today.load(client: client) } }
        }
    }

    // MARK: status cards — one row across the full width when there is room, two columns on a narrow screen

    private func cards(_ cards: [Card]) -> some View {
        let usable = max(width - 32, 0)
        let columns = max(1, min(cards.count, Int(usable / 170)))
        let ids = cards.map(\.id)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns), spacing: 10) {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(ThemeStore.rag(card.rag)).frame(height: 5)
                    Text(card.cardKey.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(connection.theme.muted)
                    Text(card.comment).font(.subheadline).foregroundStyle(connection.theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .draggable(card.id)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let id = dropped.first else { return false }
                    cardOrder.move(id, onto: card.id, among: ids)
                    return true
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(card.cardKey), \(card.rag). \(card.comment)")
            }
        }
    }

    // MARK: the shelf

    private var groups: [ShelfGroup] {
        groupOrder.sorted([
            ShelfGroup(id: "inPlan", title: "In plan", items: home.inPlan),
            ShelfGroup(id: "seeds", title: "Seeds", items: home.seeds),
            ShelfGroup(id: "released", title: "Released", items: home.released),
        ].filter { !$0.items.isEmpty })
    }

    private var shelf: some View {
        let all = groups
        let laidOut = rows(all)
        // The order on screen (short groups may have moved up beside others), so a drop lands where it looks like it will.
        let ids = laidOut.flatMap { $0 }.map(\.id)
        return VStack(alignment: .leading, spacing: 18) {
            Text("The shelf").font(.serif(26))
            ForEach(Array(laidOut.enumerated()), id: \.offset) { _, row in
                ShelfRowLayout {
                    ForEach(row) { g in
                        groupView(g, alone: row.count == 1, ids: ids)
                            .rowWidth((row.count == 1 || isCollapsed(g.id)) ? nil : naturalWidth(g))
                    }
                }
            }
            if all.isEmpty { Text("Nothing on the shelf yet.").foregroundStyle(connection.theme.muted) }
        }
    }

    private let cardPadding: CGFloat = 14

    /// The width a group needs to show all its covers in one line, inside its card.
    private func naturalWidth(_ g: ShelfGroup) -> CGFloat {
        if isCollapsed(g.id) { return 170 }
        return CGFloat(g.items.count) * (cardWidth + 14) - 14 + cardPadding * 2
    }

    private func isCollapsed(_ id: String) -> Bool { collapsedRaw.split(separator: ",").contains(Substring(id)) }
    private func toggleCollapsed(_ id: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    /// Short groups share a row when they fit side by side, and a short one moves up into the first
    /// row with room for it. A group too long for one line keeps a row to itself and its covers wrap.
    private func rows(_ groups: [ShelfGroup]) -> [[ShelfGroup]] {
        let usable = max(width - 32, 0), gap: CGFloat = 16
        var rows: [[ShelfGroup]] = [], used: [CGFloat] = []
        for g in groups {
            let w = naturalWidth(g)
            if let r = used.indices.first(where: { used[$0] + gap + w <= usable }) {
                rows[r].append(g); used[r] += gap + w
            } else {
                rows.append([g]); used.append(w)
            }
        }
        return rows
    }

    private func groupView(_ g: ShelfGroup, alone: Bool, ids: [String]) -> some View {
        let collapsed = isCollapsed(g.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: g.title, count: g.items.count, grip: true)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .draggable(g.id)
                Spacer(minLength: 8)
                Button { withAnimation(.snappy) { toggleCollapsed(g.id) } } label: {
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .foregroundStyle(connection.theme.muted).padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Expand \(g.title)" : "Collapse \(g.title)")
            }
            if !collapsed {
                // Covers wrap onto new lines instead of scrolling sideways.
                FlowLayout(spacing: 14) {
                    ForEach(g.items) { item in shelfCard(item) }
                }
            }
        }
        .padding(cardPadding)
        // A collapsed group, or one alone on its row, stretches to share the width; an open one in company keeps its size.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlay {
            if targetedGroup == g.id {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(connection.theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { dropped, _ in
            guard let id = dropped.first else { return false }
            groupOrder.move(id, onto: g.id, among: ids)
            return true
        } isTargeted: { inside in
            if inside { targetedGroup = g.id } else if targetedGroup == g.id { targetedGroup = nil }
        }
    }

    private func shelfCard(_ item: ShelfItem) -> some View {
        let card = VStack(alignment: .leading, spacing: 4) {
            CoverView(url: client.asset(item.coverUrl), seed: item.isSeed)
                .overlay {
                    if selected == item.id {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(connection.theme.accent, lineWidth: 3)
                    }
                }
            Text(item.title).font(.serif(15, relativeTo: .subheadline)).lineLimit(2)
                .foregroundStyle(connection.theme.text)
            Text(Fmt.stateLabel(item)).font(.caption).foregroundStyle(connection.theme.muted).lineLimit(1)
            Text(Fmt.when(item.activityAt)).font(.caption2).foregroundStyle(connection.theme.faint)
        }
        .frame(width: cardWidth, alignment: .leading)
        return Group {
            if item.opensPanel {
                Button { selected = item.id } label: { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
        .accessibilityElement(children: .combine)
    }
}
