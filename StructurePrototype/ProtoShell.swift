// THROWAWAY prototype shell (ADR 0.60.0 Sprint 2): the app's floating glass bar (Home, Godric, Panels) and tray,
// so Structure is tested as one panel among others. Copied in spirit from the Codex prototype.
import SwiftUI

@main
struct StructureProtoApp: App {
    @State private var store = StructureStore()
    var body: some Scene { WindowGroup { ProtoShell().environment(store) } }
}

private let stages = ["Planning", "Ideation", "Codex", "Structure", "Creation", "Editing", "Production", "Proof", "Pre-publish", "Publishing", "Review"]
private let glassTintColor = Color(.systemGray).opacity(0.16)

struct ProtoShell: View {
    @Environment(StructureStore.self) private var store
    @State private var home = false
    @State private var tray = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var regular: Bool { sizeClass == .regular }
    private var size: CGFloat { regular ? 60 : 44 }

    var body: some View {
        @Bindable var store = store
        ZStack {
            if home { VStack(spacing: 10) { Image(systemName: "house").font(.largeTitle); Text("Home (stub)").font(.title2.weight(.semibold)); Text("Panels, then Structure.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground)) }
            else { StructureRoot() }
            if tray {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { withAnimation(.snappy) { tray = false } }
                VStack { Spacer(); trayView }.padding(.bottom, regular ? 86 : 70).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .animation(.snappy, value: tray)
        .sheet(isPresented: Binding(get: { store.godricOpen && !store.isSplit }, set: { store.godricOpen = $0 })) { GodricView() }
        .onAppear {
            let a = ProcessInfo.processInfo.arguments
            if a.contains("-openChapter") { store.openAct = "act1"; if let c = store.acts[1].chapters.first(where: { $0.state == .active }) { Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); store.open(c.id) } } }
        }
    }

    private var bar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                round("house", active: home && !tray) { withAnimation(.snappy) { tray = false; home = true } }
                pill(store.currentChapterID != nil && !home ? "Godric" : "Ask Godric", "sparkles") { store.godricOpen.toggle() }
                round("square.grid.2x2", active: tray || !home) { tray.toggle() }
            }
        }.padding(.top, 4).padding(.bottom, 2).frame(maxWidth: .infinity)
    }
    private func round(_ symbol: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { Image(systemName: symbol).font((regular ? Font.title3 : .body).weight(.semibold)).foregroundStyle(active ? Color.accentColor : Color.primary).frame(width: size, height: size).contentShape(Circle()) }
            .buttonStyle(.plain).glassEffect(.regular.tint(glassTintColor).interactive(), in: .circle)
    }
    private func pill(_ title: String, _ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { HStack(spacing: 8) { Image(systemName: symbol); Text(title) }.font((regular ? Font.title3 : .subheadline).weight(.semibold)).foregroundStyle(.primary).padding(.horizontal, regular ? 32 : 20).frame(height: size).contentShape(Capsule()) }
            .buttonStyle(.plain).glassEffect(.regular.tint(glassTintColor).interactive(), in: .capsule)
    }
    private var trayView: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: regular ? 4 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("WORKFLOW").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(stages, id: \.self) { s in
                    let live = s == "Structure"; let current = live && !home
                    Button { if live { withAnimation(.snappy) { tray = false; home = false } } } label: {
                        Text(s).font(.subheadline.weight(current ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(current ? Color.white : Color.primary).background(current ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { if !live { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [4])) } }.opacity(live ? 1 : 0.45)
                    }.buttonStyle(.plain).disabled(!live)
                }
            }
        }.padding(14).frame(maxWidth: 520).glassEffect(.regular.tint(glassTintColor), in: .rect(cornerRadius: 24)).padding(.horizontal, 12)
    }
}
