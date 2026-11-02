import SwiftUI

/// Covers are fetched once and kept: in memory for this run, and on disk between runs. A cover's address carries its
/// own version (?v=), so a replaced cover has a new address and is fetched again; nothing stale is ever shown.
@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.countLimit = 200
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let (data, _) = try? await session.data(from: url), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct CoverView: View {
    let url: URL?
    let seed: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: seed ? "sparkles" : "book.closed").font(.title2).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageStore.shared.cached(url) { image = hit; return }
            image = await ImageStore.shared.image(url)
        }
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

/// A slim glass band across the top with the page scrolling behind it: a small tag on a pre-production or dev
/// build (the production app shows none), the panel's title if it has one, and the settings gear at the right.
struct TopBand: ViewModifier {
    var enabled = true
    var title: String?
    @Environment(ConnectionModel.self) private var connection

    private var tag: String? {
        guard let env = connection.instance?.environment, env != "production" else { return nil }
        return Fmt.environmentName(env)
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if enabled {
                HStack(spacing: 10) {
                    if let title { Text(title).font(.serif(22)) }
                    if let tag {
                        Text(tag).font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(tag == "PRE-PROD" ? Color.orange : Color.teal, in: Capsule())
                    }
                    Spacer()
                    Menu {
                        Section("About Greymere") {
                            Label("iOS \(appVersion)", systemImage: "iphone")
                            if let instance = connection.instance {
                                Label("Server \(instance.version)", systemImage: "server.rack")
                                Label(Fmt.environmentName(instance.environment), systemImage: "leaf")
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape").font(.body.weight(.semibold)).padding(7)
                            .foregroundStyle(connection.theme.text)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 16).padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background {
                    Rectangle().fill(.clear)
                        .glassEffect(.regular.tint(connection.theme.glassTint), in: .rect)
                        .ignoresSafeArea(edges: .top)
                }
            }
        }
    }
}

extension View {
    func topBand(_ enabled: Bool = true, title: String? = nil) -> some View { modifier(TopBand(enabled: enabled, title: title)) }

    /// The floating glass bar at the bottom of every screen, in the manner of the Music app: Home, the Ask Godric
    /// pill, and Panels (which raises the tray of workflow stages).
    func glassBar(isOpen: Bool, inline: AnyView? = nil, action: @escaping () -> Void) -> some View {
        modifier(GlassBar(isOpen: isOpen, inline: inline, action: action))
    }
}

struct GlassBar: ViewModifier {
    let isOpen: Bool
    /// A screen's own actions, set into the bar's row instead of a row of their own (a phone on its side has no room to spare).
    var inline: AnyView?
    let action: () -> Void
    @Environment(ConnectionModel.self) private var connection
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Bigger on an iPad, where a phone-sized bar gets lost.
    private var regular: Bool { sizeClass == .regular }
    private var size: CGFloat { regular ? 60 : 44 }

    private func round(_ symbol: String, label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol).font((regular ? Font.title3 : .body).weight(.semibold))
                .foregroundStyle(active ? connection.theme.accent : connection.theme.text)
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(connection.theme.glassTint).interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    round("house", label: "Home", active: shell.destination == .home && !shell.trayOpen) { shell.goHome() }
                    if let inline { inline }
                    Button(action: action) {
                        HStack(spacing: regular ? 12 : 8) {
                            Image(systemName: "sparkles").font((regular ? Font.title3 : .subheadline).weight(.semibold))
                            Text(isOpen ? "Close Godric" : "Ask Godric").font((regular ? Font.title3 : .subheadline).weight(.semibold))
                        }
                        .foregroundStyle(connection.theme.text)
                        .padding(.horizontal, regular ? 32 : 20).frame(height: size)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(connection.theme.glassTint).interactive(), in: .capsule)
                    .accessibilityLabel("Talk to Godric")
                    round("square.grid.2x2", label: "Panels", active: shell.trayOpen || shell.destination != .home) { shell.trayOpen.toggle() }
                }
            }
            .padding(.top, 4).padding(.bottom, 2)
            .frame(maxWidth: .infinity)
        }
    }
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

/// The divider between a panel and the Godric chat docked beside it on an iPad: drag it to give Godric more or less room.
/// Dragging left widens Godric; the panel keeps at least `minPanel` points.
struct DockHandle: View {
    @Binding var width: Double
    var available: CGFloat
    var minPanel: CGFloat = 300
    @State private var start: Double?
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        ZStack {
            Rectangle().fill(connection.theme.faint.opacity(0.35)).frame(width: 1)
            Capsule().fill(connection.theme.muted.opacity(0.55)).frame(width: 4, height: 44)
        }
        .frame(width: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if start == nil { start = width }
                    let limit = max(240, Double(available - minPanel))
                    width = min(max((start ?? width) - Double(v.translation.width), 220), limit)
                }
                .onEnded { _ in start = nil }
        )
        .accessibilityLabel("Resize Godric")
        .accessibilityHint("Drag to change how much room Godric has")
    }
}

/// An action that belongs to the screen, set in the bottom glass bar: the same height, glass and type as the Ask Godric
/// pill (a design rule for the app: what the author can do here appears in that bar, in glass, when it is needed).
/// `prominent` tints it with the accent for the main action. With no title it is a round button.
struct GlassPill: View {
    var title: String?
    var systemImage: String?
    var prominent = false
    var label: String?
    let action: () -> Void
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isEnabled) private var enabled

    private var regular: Bool { sizeClass == .regular }
    private var size: CGFloat { regular ? 60 : 44 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: regular ? 12 : 8) {
                if let systemImage { Image(systemName: systemImage).font((regular ? Font.title3 : .subheadline).weight(.semibold)) }
                if let title { Text(title).font((regular ? Font.title3 : .subheadline).weight(.semibold)).lineLimit(1) }
            }
            .foregroundStyle(prominent ? connection.theme.accent : connection.theme.text)
            .padding(.horizontal, title == nil ? 0 : (regular ? 32 : 20))
            .frame(width: title == nil ? size : nil, height: size)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(prominent ? connection.theme.accent.opacity(0.28) : connection.theme.glassTint).interactive(), in: .capsule)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label ?? title ?? "")
    }
}
