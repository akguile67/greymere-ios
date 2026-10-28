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

private struct HomeContent: View {
    let home: HomeModel
    let client: APIClient
    @Binding var selected: String?
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = home.summary {
                    cards(summary.cards)
                    shelf
                } else if home.failed {
                    Text("Home couldn't be loaded. Pull down to try again.").foregroundStyle(connection.theme.muted)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .background(connection.theme.background.ignoresSafeArea())
        .refreshable { await home.load(using: client) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await home.load(using: client) } }
        }
    }

    private func cards(_ cards: [Card]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(ThemeStore.rag(card.rag)).frame(height: 5)
                    Text(card.cardKey.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(connection.theme.muted)
                    Text(card.comment).font(.subheadline).foregroundStyle(connection.theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(card.cardKey), \(card.rag). \(card.comment)")
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The shelf").font(.serif(26))
            group("In plan", home.inPlan)
            group("Seeds", home.seeds)
            group("Released", home.released)
            if home.inPlan.isEmpty && home.seeds.isEmpty && home.released.isEmpty {
                Text("Nothing on the shelf yet.").foregroundStyle(connection.theme.muted)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ShelfItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: title, count: items.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in shelfCard(item) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func shelfCard(_ item: ShelfItem) -> some View {
        let width: CGFloat = sizeClass == .regular ? 124 : 104
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
        .frame(width: width, alignment: .leading)
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
