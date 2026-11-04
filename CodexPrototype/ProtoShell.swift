// THROWAWAY prototype shell (ADR 0.59.0 Sprint 1): imitates the real app's floating glass bar (Home, Ask Godric, Panels)
// and the workflow tray, so the Codex is tested as one panel among others, reached the way the author will reach it.
import SwiftUI

enum ProtoDest: Equatable { case home, codex }

@MainActor @Observable
final class ShellState {
    var dest: ProtoDest = .home
    var trayOpen = false
}

private let stages = ["Planning", "Ideation", "Codex", "Structure", "Creation", "Editing", "Production", "Proof", "Pre-publish", "Publishing", "Review"]
private let glassTintColor = Color(.systemGray).opacity(0.16)

struct ProtoShell: View {
    @Environment(CodexStore.self) private var store
    @State private var shell = ShellState()
    @State private var godric = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var regular: Bool { sizeClass == .regular }
    private var size: CGFloat { regular ? 60 : 44 }

    var body: some View {
        ZStack {
            ProtoHome().opacity(shell.dest == .home ? 1 : 0).allowsHitTesting(shell.dest == .home)
            if shell.dest == .codex { CodexRoot().transition(.opacity) }
            if shell.trayOpen {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { withAnimation(.snappy) { shell.trayOpen = false } }
                VStack { Spacer(); tray }.padding(.bottom, regular ? 86 : 70).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .animation(.snappy, value: shell.trayOpen)
        .sheet(isPresented: $godric) { GodricStub() }
        .onAppear {
            // Test hook for recordings: -startCodex opens Codex with Harrow Hall selected; -autoToggle flips full screen.
            let a = ProcessInfo.processInfo.arguments
            guard a.contains("-startCodex") else { return }
            shell.dest = .codex; store.selection = 2
            if a.contains("-autoToggle") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3)); store.fullScreen = true
                    try? await Task.sleep(for: .seconds(3)); store.fullScreen = false
                }
            }
        }
    }

    private var bar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                round("house", active: shell.dest == .home && !shell.trayOpen) { withAnimation(.snappy) { shell.trayOpen = false; shell.dest = .home } }
                // A screen's own action sits in the bar: with an entry open in the Codex, that is Edit.
                if shell.dest == .codex, store.currentEntry != nil {
                    pill("Edit", "pencil") { store.pendingAction = .edit }
                    Menu { EntryActionButtons() } label: {
                        Image(systemName: "ellipsis").font((regular ? Font.title3 : .body).weight(.semibold))
                            .foregroundStyle(Color.primary).frame(width: size, height: size).contentShape(Circle())
                    }
                    .glassEffect(.regular.tint(glassTintColor).interactive(), in: .circle)
                } else if shell.dest == .codex {
                    pill("New", "plus") { store.newToken += 1 }
                }
                pill(store.currentEntry != nil && shell.dest == .codex ? "Godric" : "Ask Godric", "sparkles") { godric = true }
                round("square.grid.2x2", active: shell.trayOpen || shell.dest != .home) { shell.trayOpen.toggle() }
            }
        }
        .padding(.top, 4).padding(.bottom, 2).frame(maxWidth: .infinity)
    }

    private func round(_ symbol: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol).font((regular ? Font.title3 : .body).weight(.semibold))
                .foregroundStyle(active ? Color.accentColor : Color.primary).frame(width: size, height: size).contentShape(Circle())
        }.buttonStyle(.plain).glassEffect(.regular.tint(glassTintColor).interactive(), in: .circle)
    }
    private func pill(_ title: String, _ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 8) { Image(systemName: symbol); Text(title) }
                .font((regular ? Font.title3 : .subheadline).weight(.semibold)).foregroundStyle(.primary)
                .padding(.horizontal, regular ? 32 : 20).frame(height: size).contentShape(Capsule())
        }.buttonStyle(.plain).glassEffect(.regular.tint(glassTintColor).interactive(), in: .capsule)
    }

    private var tray: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: regular ? 4 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("WORKFLOW").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(stages, id: \.self) { s in
                    let live = s == "Codex"; let current = live && shell.dest == .codex
                    Button { if live { withAnimation(.snappy) { shell.trayOpen = false; shell.dest = .codex } } } label: {
                        Text(s).font(.subheadline.weight(current ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(current ? Color.white : Color.primary)
                            .background(current ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { if !live { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [4])) } }
                            .opacity(live ? 1 : 0.45)
                    }.buttonStyle(.plain).disabled(!live)
                }
            }
        }
        .padding(14).frame(maxWidth: 520).glassEffect(.regular.tint(glassTintColor), in: .rect(cornerRadius: 24)).padding(.horizontal, 12)
    }
}

struct ProtoHome: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "house").font(.largeTitle).foregroundStyle(.secondary)
            Text("Home (stub)").font(.title2.weight(.semibold))
            Text("Tap Panels, then Codex.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground))
    }
}

struct GodricStub: View {
    @Environment(CodexStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let id = store.godricContext, let e = store.entry(id) {
                    Label("Looking at: \(e.name) (the open Codex entry)", systemImage: "eye").font(.footnote)
                } else { Text("No Codex entry open.").font(.footnote).foregroundStyle(.secondary) }
                Text("Godric chat (stub). On iPad this docks beside the panel.").foregroundStyle(.secondary)
            }
            .navigationTitle("Godric").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
