import SwiftUI
import PhotosUI

/// An entry's image: look at it, add one from Photos, approve or reject it, delete it, or have Godric make one
/// (characters and locations). Generating spends money, so it only runs after a confirmation, and nothing is kept until
/// the author presses Use this image.
struct CodexPortraitSheet: View {
    @Bindable var model: CodexModel
    let client: APIClient
    let id: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    private enum Phase { case idle, crafting, prompt, generating, preview }
    @State private var phase: Phase = .idle
    @State private var prompt = ""
    @State private var preview: CodexGenerated?
    @State private var pick: PhotosPickerItem?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmGenerate = false
    @State private var confirmDelete = false

    private var theme: ThemeStore { connection.theme }
    private var entry: CodexEntry? { model.entry(id) }
    private var path: String? { model.details[id]?.portraitPath ?? entry?.portraitPath }
    private var status: String? { model.details[id]?.portraitStatus ?? entry?.portraitStatus }
    private var canGenerate: Bool { entry?.type == .characters || entry?.type == .locations }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    image
                    if let message { Text(message).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(12).glassEffect(.regular, in: .rect(cornerRadius: 14)) }
                    if phase == .idle { actions } else { generator }
                }
                .padding()
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(entry?.name ?? "Image").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: pick) { _, item in if let item { Task { await upload(item) } } }
        .confirmationDialog("Make an image?", isPresented: $confirmGenerate, titleVisibility: .visible) {
            Button("Generate (about $0.04)") { Task { await generate() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It costs about $0.04 and takes about 15 seconds. Nothing is kept until you use it.") }
        .confirmationDialog("Delete this image?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete image", role: .destructive) { Task { await run { await model.deletePortrait(id) } } }
            Button("Keep it", role: .cancel) {}
        } message: { Text("The file is removed. The next image made for this entry starts fresh.") }
    }

    // MARK: the picture

    @ViewBuilder private var image: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        let url: URL? = phase == .preview ? preview.flatMap { URL(string: $0.imageUrl) } : client.asset(path)
        VStack(spacing: 8) {
            if let url {
                AsyncImage(url: url) { p in
                    if let i = p.image { i.resizable().scaledToFit() } else { ProgressView().frame(height: 240) }
                }
                .frame(maxWidth: 420).clipShape(shape)
            } else {
                shape.fill(Color(.secondarySystemFill)).frame(width: 220, height: 280)
                    .overlay { VStack { Image(systemName: entry?.type.symbol ?? "photo").font(.largeTitle); Text("No image yet").font(.footnote) }.foregroundStyle(theme.muted) }
            }
            if phase == .preview { Text("New image, not saved yet").font(.caption).foregroundStyle(theme.muted) }
            else if path != nil { statusBadge }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch status {
        case "approved": ("Approved", .green); case "rejected": ("Rejected", .red); default: ("Waiting for your review", .orange)
        }
        return Text(text).font(.caption.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 4).background(color.opacity(0.15), in: .capsule)
    }

    // MARK: actions

    private var actions: some View {
        VStack(spacing: 10) {
            if path != nil {
                HStack(spacing: 10) {
                    button("Approve", "checkmark.circle", disabled: status == "approved") { Task { await run { await model.approvePortrait(id) } } }
                    button("Reject", "xmark.circle", disabled: status == "rejected") { Task { await run { await model.rejectPortrait(id) } } }
                }
            }
            PhotosPicker(selection: $pick, matching: .images) { CodexTile(title: path == nil ? "Choose from Photos" : "Replace from Photos", symbol: "photo.on.rectangle", color: theme.text) }
                .disabled(busy)
            if canGenerate { button(path == nil ? "Make one with Godric" : "Make a new one with Godric", "sparkles") { Task { await craft() } } }
            else { Text("Godric makes images for characters and locations.").font(.caption).foregroundStyle(theme.faint) }
            if path != nil { button("Delete image", "trash", destructive: true) { confirmDelete = true } }
            if busy { ProgressView().padding(.top, 4) }
        }
    }

    private func button(_ title: String, _ symbol: String, destructive: Bool = false, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(title, symbol, destructive: destructive) }.buttonStyle(.plain).disabled(disabled || busy).opacity(disabled ? 0.4 : 1)
    }

    private func tile(_ title: String, _ symbol: String, destructive: Bool = false) -> some View {
        CodexTile(title: title, symbol: symbol, color: destructive ? .red : theme.text)
    }

    // MARK: Godric's image

    @ViewBuilder private var generator: some View {
        switch phase {
        case .crafting: HStack { ProgressView(); Text("Godric is writing the prompt…").foregroundStyle(theme.muted) }
        case .generating: HStack { ProgressView(); Text("Making the image, about 15 seconds…").foregroundStyle(theme.muted) }
        case .prompt, .preview:
            VStack(alignment: .leading, spacing: 10) {
                Text("The prompt (edit it if you like)").font(.footnote).foregroundStyle(theme.muted)
                TextEditor(text: $prompt).scrollContentBackground(.hidden).frame(minHeight: 160).padding(10).glassEffect(.regular, in: .rect(cornerRadius: 16))
                if phase == .preview, let c = preview?.costUsd { Text(String(format: "That run cost about $%.2f.", c)).font(.caption).foregroundStyle(theme.faint) }
                if phase == .preview {
                    button("Use this image", "checkmark") { Task { await useImage() } }
                    button("Make another (about $0.04)", "arrow.clockwise") { confirmGenerate = true }
                } else {
                    button("Generate (about $0.04)", "sparkles") { confirmGenerate = true }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                button("Back", "chevron.left") { phase = .idle; preview = nil; message = nil }
            }
        default: EmptyView()
        }
    }

    private func craft() async {
        message = nil; phase = .crafting
        switch await model.craftPrompt(id) {
        case .success(let p): prompt = p; phase = .prompt
        case .failure(let f): message = f.text; phase = .idle
        }
    }

    private func generate() async {
        message = nil; phase = .generating
        switch await model.generatePortrait(id, prompt: prompt) {
        case .success(let g): preview = g; phase = .preview
        case .failure(let f): message = f.text; phase = .prompt
        }
    }

    private func useImage() async {
        guard let url = preview?.imageUrl else { return }
        await run { await model.savePortrait(id, url: url) }
        phase = .idle; preview = nil
    }

    private func run(_ work: () async -> String?) async {
        busy = true; message = nil
        message = await work()
        busy = false
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true; message = nil; defer { busy = false; pick = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else { message = "That photo could not be read."; return }
        let longest = max(ui.size.width, ui.size.height)
        let scale = min(1, 2048 / longest)
        let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = img.jpegData(compressionQuality: 0.85) else { message = "That photo could not be prepared."; return }
        message = await model.uploadPortrait(id, jpeg: jpeg)
    }
}

private struct CodexTile: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        Label(title, systemImage: symbol).font(.body.weight(.medium)).foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}
