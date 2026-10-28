import SwiftUI

struct EnvironmentBar: View {
    let instance: Instance
    @Environment(ConnectionModel.self) private var connection

    private var tint: Color {
        switch instance.environment {
        case "production": return connection.theme.accent
        case "pre-production": return .orange
        default: return .teal
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(Fmt.environmentName(instance.environment)).font(.caption.weight(.semibold))
            Text("server \(instance.version)").font(.caption).foregroundStyle(connection.theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct CoverView: View {
    let url: URL?
    let seed: Bool
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: seed ? "sparkles" : "book.closed").font(.title2).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

struct SectionLabel: View {
    let title: String
    let count: Int?
    var grip = false
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
            if let count { Text("\(count)").font(.caption).foregroundStyle(connection.theme.faint) }
            if grip {
                Image(systemName: "line.3.horizontal").font(.caption.weight(.semibold))
                    .foregroundStyle(connection.theme.faint).padding(.leading, 4)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(connection.theme.muted)
    }
}

/// The environment pill on a glass band across the top, with the page scrolling behind it.
struct EnvironmentBarInset: ViewModifier {
    var enabled = true
    @Environment(ConnectionModel.self) private var connection

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if enabled, let instance = connection.instance {
                EnvironmentBar(instance: instance)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        Rectangle().fill(.clear)
                            .glassEffect(.regular, in: .rect)
                            .ignoresSafeArea(edges: .top)
                    }
            }
        }
    }
}

extension View {
    func environmentBar(_ enabled: Bool = true) -> some View { modifier(EnvironmentBarInset(enabled: enabled)) }
}

// MARK: shelf rows

private struct RowWidthKey: LayoutValueKey { static let defaultValue: CGFloat? = nil }

extension View {
    /// The width a shelf group needs when it is open; nil means it takes what the row can give.
    func rowWidth(_ width: CGFloat?) -> some View { layoutValue(key: RowWidthKey.self, value: width) }
}

/// One row of shelf groups. Open groups get the width they need; collapsed ones share what is left, and only
/// stretch across the whole row when every group in it is collapsed. Never wider than the room it is given.
struct ShelfRowLayout: Layout {
    var spacing: CGFloat = 16
    var minFlexible: CGFloat = 150
    var maxFlexibleBesideOpen: CGFloat = 190

    private func widths(_ subviews: Subviews, available: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0[RowWidthKey.self] }
        let n = subviews.count
        let room = max(available - spacing * CGFloat(max(n - 1, 0)), 0)
        let fixedTotal = natural.compactMap { $0 }.reduce(0, +)
        let fixedCount = natural.compactMap { $0 }.count
        let flexCount = n - fixedCount
        guard fixedTotal + CGFloat(flexCount) * minFlexible <= room else {
            // Too narrow: open groups give way proportionally (their covers wrap), collapsed ones keep a minimum.
            let scale = max((room - CGFloat(flexCount) * minFlexible) / max(fixedTotal, 1), 0)
            return natural.map { $0.map { $0 * scale } ?? minFlexible }
        }
        if fixedCount == 0 {
            // Everything collapsed (or one group alone): share the whole row evenly.
            return natural.map { _ in room / CGFloat(max(flexCount, 1)) }
        }
        // Open groups stretch to fill the row, so every row lines up with the others; collapsed ones stay pill-sized.
        let pill = flexCount > 0 ? min(maxFlexibleBesideOpen, (room - fixedTotal) / CGFloat(flexCount)) : 0
        let spare = max(room - fixedTotal - pill * CGFloat(flexCount), 0)
        return natural.map { $0.map { $0 + spare / CGFloat(fixedCount) } ?? pill }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? 600
        let w = widths(subviews, available: available)
        let height = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? (w.reduce(0, +) + spacing * CGFloat(max(w.count - 1, 0))), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews, available: bounds.width)
        var x = bounds.minX
        for (view, width) in zip(subviews, w) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}
