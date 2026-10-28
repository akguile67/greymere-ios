import SwiftUI

/// Home: the status cards and the shelf. On a wide screen it fills the screen until a cover is
/// tapped, then Book Details slides in beside it; on a narrow one Book Details is pushed.
struct HomeScreen: View {
    let client: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(ConnectionModel.self) private var connection
    @State private var home = HomeModel()
    @State private var selected: String?

    var body: some View {
        Group {
            if sizeClass == .regular {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        HomeContent(home: home, client: client, selected: $selected)
                        if let item = home.item(selected), let detail = item.detail {
                            Divider()
                            BookDetailView(item: item, figures: detail, client: client, onClose: { selected = nil })
                                .frame(width: max(380, geo.size.width * 0.46))
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .animation(.snappy, value: selected)
                }
            } else {
                NavigationStack {
                    HomeContent(home: home, client: client, selected: $selected)
                        .navigationDestination(item: $selected) { id in
                            if let item = home.item(id), let detail = item.detail {
                                BookDetailView(item: item, figures: detail, client: client, onClose: nil)
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .task { await home.load(using: client) }
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
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var width: CGFloat = 0
    @State private var cardOrder = OrderStore(key: "cards")
    @State private var groupOrder = OrderStore(key: "shelfGroups")

    private var cardWidth: CGFloat { sizeClass == .regular ? 124 : 104 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = home.summary {
                    cards(cardOrder.sorted(summary.cards))
                    shelf
                } else if home.failed {
                    Text("Home couldn't be loaded. Pull down to try again.").foregroundStyle(connection.theme.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        }
        .background(connection.theme.background.ignoresSafeArea())
        .refreshable { await home.load(using: client) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await home.load(using: client) } }
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
        let ids = all.map(\.id)
        return VStack(alignment: .leading, spacing: 18) {
            Text("The shelf").font(.serif(26))
            ForEach(Array(rows(all).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 28) {
                    ForEach(row) { g in groupView(g, alone: row.count == 1, ids: ids) }
                }
            }
            if all.isEmpty { Text("Nothing on the shelf yet.").foregroundStyle(connection.theme.muted) }
        }
    }

    private func naturalWidth(_ g: ShelfGroup) -> CGFloat {
        CGFloat(g.items.count) * (cardWidth + 14) - 14
    }

    /// Small groups share a row when they fit side by side, and a short one moves up into the first
    /// row with room for it. A long group keeps a row to itself and scrolls.
    private func rows(_ groups: [ShelfGroup]) -> [[ShelfGroup]] {
        let usable = max(width - 32, 0), gap: CGFloat = 28
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
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: g.title, count: g.items.count, grip: true)
                .padding(.vertical, 6).padding(.trailing, 24)
                .contentShape(Rectangle())
                .draggable(g.id)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(g.items) { item in shelfCard(item) }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        .frame(width: alone ? nil : naturalWidth(g), alignment: .leading)
        .frame(maxWidth: alone ? .infinity : nil, alignment: .leading)
        .dropDestination(for: String.self) { dropped, _ in
            guard let id = dropped.first else { return false }
            groupOrder.move(id, onto: g.id, among: ids)
            return true
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
            if item.hasDetails {
                Button { selected = item.id } label: { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
        .accessibilityElement(children: .combine)
    }
}
