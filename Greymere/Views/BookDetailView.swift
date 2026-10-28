import SwiftUI

/// Book Details, read-only: what the desktop's Book Details screen shows, as the server sends it.
struct BookDetailView: View {
    let item: ShelfItem
    let figures: BookFigures
    let client: APIClient
    let onClose: (() -> Void)?
    @Environment(ConnectionModel.self) private var connection
    @State private var open: Set<String> = []

    private var f: BookFigures { figures }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let onClose {
                    HStack {
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").font(.body.weight(.semibold)).padding(6) }
                            .buttonStyle(.glass).buttonBorderShape(.circle)
                            .accessibilityLabel("Close")
                    }
                }
                hero
                statGrid
                detailsCard
                if !f.overdueSteps.isEmpty { overdueCard }
                if let synopsis = f.synopsis { synopsisCard(synopsis) }
            }
            .padding(16)
        }
        .background(connection.theme.background.ignoresSafeArea())
        .navigationTitle(f.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverView(url: client.asset(item.coverUrl), seed: false).frame(width: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(Fmt.seriesLine(template: f.template, series: f.seriesName))
                    .font(.caption).foregroundStyle(connection.theme.muted)
                Text(f.title).font(.serif(26))
                if let excerpt = excerpt { Text(excerpt).font(.footnote).foregroundStyle(connection.theme.muted).lineLimit(4) }
                badges
            }
        }
    }

    private var excerpt: String? {
        guard let s = f.synopsis else { return nil }
        let flat = s.replacingOccurrences(of: #"^#[^\n]*\n+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "*", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > 220 ? String(flat.prefix(220)) + "…" : flat
    }

    private var badges: some View {
        FlowLayout(spacing: 6) {
            badge(Fmt.phase(f.status))
            if let h = f.health { badge(h.uppercased(), tint: ThemeStore.rag(h)) }
            badge("\(Fmt.number(f.wordCount)) words")
            if let c = f.chapterCount, c > 0 { badge("\(c) chapters") }
        }
    }

    private func badge(_ text: String, tint: Color? = nil) -> some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
            .background((tint ?? .secondary).opacity(0.18), in: .capsule)
            .foregroundStyle(tint ?? connection.theme.muted)
            .fixedSize()
    }

    // MARK: the five figures

    private var statGrid: some View {
        let varianceSub = f.planDriftDays == nil ? "plan not committed"
            : (f.planDriftDays! > 0 ? "ahead of plan" : f.planDriftDays! < 0 ? "behind plan" : "on plan")
        let editingPct = (f.chapterCount ?? 0) > 0
            ? "\(Int((Double(f.chaptersDone ?? 0) / Double(f.chapterCount!) * 100).rounded()))% chapters done" : "—"
        let editingSub = [ (f.chapterCount ?? 0) > 0 ? "\(f.chaptersDone ?? 0) / \(f.chapterCount!) done" : nil,
                           f.openIssues.map { "\($0) open issues" } ].compactMap { $0 }.joined(separator: " · ")
        let contingencySub = f.currentStep.map { s in
            "\(s.name ?? "") by \(Fmt.date(s.date))" + (s.band.map { " · \($0)" } ?? "")
        } ?? "no current step"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            stat("Manuscript", Fmt.number(f.wordCount), "target \(Fmt.number(f.wordTarget))")
            stat("Editing", editingPct, editingSub)
            stat("Publish date", Fmt.date(f.publishDate), f.daysSlack.map { Fmt.signed($0, unit: "d") + " to publish" } ?? "")
            stat("Variance to plan", Fmt.signed(f.planDriftDays, unit: "d"),
                 varianceSub + (f.health.map { " · health: \($0)" } ?? ""))
            stat("Contingency in plan", Fmt.signed(f.contingency, unit: "wd"), contingencySub)
        }
    }

    private func stat(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(connection.theme.muted)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(connection.theme.text)
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(connection.theme.muted) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: cards

    private var detailsCard: some View {
        collapsible("Book details") {
            row("Series", f.seriesName ?? "—")
            row("Template", f.template ?? "not set")
            row("Status", Fmt.phase(f.status))
            row("Priority", f.priority.map { "P\($0)" } ?? "not set")
            row("Chapter target", f.chapterTarget.map(String.init) ?? "not set")
            row("Word target", f.wordTarget.map { Fmt.number($0) } ?? "not set")
            row("Word count (actual)", Fmt.number(f.wordCount))
            row("Chapters", (f.chapterCount ?? 0) > 0 ? "\(f.chaptersDone ?? 0) / \(f.chapterCount!) done" : "—")
            row("Publish date", f.publishDate == nil ? "not set" : Fmt.date(f.publishDate))
            row("Scheduling mode", f.schedulingMode == "backward" ? "Backward (anchor on publish)" : "Forward (from start)")
        }
    }

    private var overdueCard: some View {
        card("Overdue steps") {
            ForEach(f.overdueSteps) { s in
                row(s.stepName, "\(s.daysLate) days late" + (s.awaitsConfirmation ? " · waiting on you" : ""))
            }
        }
    }

    private func synopsisCard(_ text: String) -> some View {
        collapsible("Synopsis") {
            Text(.init(text)).font(.callout).foregroundStyle(connection.theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A card that shows only its title until tapped, so a long synopsis doesn't push everything else away.
    private func collapsible<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(title)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { if isOpen { open.remove(title) } else { open.insert(title) } }
            } label: {
                HStack {
                    Text(title).font(.serif(19, relativeTo: .headline))
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0)).foregroundStyle(connection.theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            if isOpen { content() }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.serif(19, relativeTo: .headline))
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(connection.theme.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(connection.theme.text)
        }
        .font(.subheadline)
    }
}

/// Items laid left to right, wrapping onto a new line when the row is full. An item wider than the row
/// is squeezed to the row's width (its text wraps) rather than stretching the whole layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                              proposal: ProposedViewSize(width: result.sizes[i].width, height: nil))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat?) -> (size: CGSize, origins: [CGPoint], sizes: [CGSize]) {
        let limit = (width?.isFinite ?? false) ? width! : CGFloat.infinity
        var origins: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            var s = v.sizeThatFits(ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil))
            if limit.isFinite && s.width > limit { s = v.sizeThatFits(ProposedViewSize(width: limit, height: nil)); s.width = min(s.width, limit) }
            if x > 0 && x + s.width > limit { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y)); sizes.append(s)
            x += s.width + spacing; rowHeight = max(rowHeight, s.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: min(maxX, limit), height: y + rowHeight), origins, sizes)
    }
}
