import SwiftUI
import Observation

/// The studio's workflow stages, in the desktop rail's order. The tray shows these and nothing else: the back-office
/// panels stay on the laptop for now. A stage is tappable only when the app has it.
enum Panel: String, CaseIterable, Identifiable, Hashable {
    case planning, ideation, codex, structure, creation, editing, production, proof, prepublish, publishing, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prepublish: "Pre-publish"
        default: rawValue.capitalized
        }
    }

    /// The panels the app has so far.
    var isAvailable: Bool { self == .ideation || self == .creation }
}

enum Destination: Equatable {
    case home
    case panel(Panel)
}

/// Where the author is: Home or one panel, and whether the tray of panels is raised. One per app, in the environment.
@MainActor @Observable
final class ShellModel {
    var destination: Destination = .home
    var trayOpen = false

    func goHome() {
        withAnimation(.snappy) { trayOpen = false; destination = .home }
    }

    func open(_ panel: Panel) {
        guard panel.isAvailable else { return }
        withAnimation(.snappy) { trayOpen = false; destination = .panel(panel) }
    }
}

/// The glass tray the Panels button raises above the bar: the workflow stages, the current one marked.
struct PanelTray: View {
    @Environment(ConnectionModel.self) private var connection
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeClass == .regular ? 4 : 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORKFLOW").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(connection.theme.muted)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Panel.allCases) { panel in
                    let current = shell.destination == .panel(panel)
                    Button { shell.open(panel) } label: {
                        Text(panel.title).font(.subheadline.weight(current ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(current ? Color.white : connection.theme.text)
                            .background(current ? connection.theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                if !panel.isAvailable {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                }
                            }
                            .opacity(panel.isAvailable ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!panel.isAvailable)
                    .accessibilityHint(panel.isAvailable ? "" : "Not in the app yet")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .glassEffect(.regular.tint(connection.theme.glassTint), in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
    }
}

/// The app once connected: Home stays alive underneath (so what was selected is still there on the way back),
/// a panel sits over it, and the tray floats over both.
struct AppShell: View {
    let client: APIClient
    @State private var home = HomeModel()
    @State private var shell = ShellModel()
    @State private var ideation = IdeationModel()
    @State private var creation = CreationModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            HomeScreen(home: home, client: client)
                .opacity(shell.destination == .home ? 1 : 0)
                .allowsHitTesting(shell.destination == .home)
                .accessibilityHidden(shell.destination != .home)
            if case .panel(.ideation) = shell.destination {
                IdeationScreen(model: ideation, home: home, client: client)
                    .transition(.opacity)
            }
            if case .panel(.creation) = shell.destination {
                CreationScreen(model: creation, home: home, client: client)
                    .transition(.opacity)
            }
            if shell.trayOpen {
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { shell.trayOpen = false } }
                VStack { Spacer(); PanelTray() }
                    .padding(.bottom, sizeClass == .regular ? 86 : 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(shell)
        .animation(.snappy, value: shell.trayOpen)
    }
}
