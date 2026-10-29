import SwiftUI

/// Godric chat: the Home thread, as the desktop's Godric panel shows it. Full screen on iPhone, docked on iPad.
struct GodricChatView: View {
    let model: GodricModel
    let client: APIClient
    var showsBar = false
    var book: ChatBook?
    var onClose: (() -> Void)?
    @Environment(ConnectionModel.self) private var connection
    @State private var draft = ""
    @State private var showHistory = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.viewing != nil { pastBanner }
            thread
            // The desktop's suggestion buttons are kept for the wide screens; on a phone they only take room.
            if sizeClass == .regular, !model.quickActions.isEmpty { quickActions }
            ChatInput(text: $draft, canSend: !model.busy && model.viewing == nil,
                      placeholder: model.viewing == nil ? "Message Godric…" : "Reading only") {
                let text = draft
                draft = ""
                Task { await model.send(text, client: client) }
            }
            .disabled(model.viewing != nil)
            .opacity(model.viewing != nil ? 0.45 : 1)
            .padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 4)
        }
        .background(connection.theme.background.ignoresSafeArea())
        .environmentBar(showsBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showHistory) { HistorySheet(model: model, client: client, isPresented: $showHistory) }
        .task(id: book?.id) { await model.open(client: client, book: book.map { ($0.id, $0.title) }) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let onClose {
                Button(action: onClose) { Image(systemName: onCloseIcon).font(.body.weight(.semibold)).padding(6) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Close Godric")
            }
            Text("Godric").font(.serif(22))
            statusChip
            Spacer()
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath").padding(6) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("History")
            Button { Task { await model.newChat(client: client) } } label: { Image(systemName: "square.and.pencil").padding(6) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("New chat")
                .disabled(model.busy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var onCloseIcon: String { "chevron.backward" }

    private var statusChip: some View {
        let (label, color): (String, Color) = switch model.status {
        case .ready: ("Ready", .green)
        case .thinking: ("Thinking…", .orange)
        case .offline: ("Offline", .red)
        }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(connection.theme.muted)
        }
    }

    private var pastBanner: some View {
        HStack {
            Text("Viewing a past conversation").font(.footnote)
            Spacer()
            Button("Continue") { Task { await model.continueViewing(client: client) } }
            Button("Back") { model.backToActive() }
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.messages) { m in
                        Bubble(message: m).id(m.id)
                    }
                    if model.busy { TypingBubble().id("typing") }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) { scrollToEnd(proxy) }
            .onChange(of: model.busy) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if model.busy { proxy.scrollTo("typing", anchor: .bottom) }
            else if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.quickActions, id: \.self) { action in
                Button { Task { await model.send(action, client: client) } } label: {
                    Text("→ \(action)").font(.footnote).multilineTextAlignment(.leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.bottom, 4)
    }
}

private struct Bubble: View {
    let message: ChatMessage
    @Environment(ConnectionModel.self) private var connection

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Bold (**x**) and line breaks only, as the desktop panel renders a reply.
    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        switch message.role {
        case .note:
            Text(message.text).font(.caption2).foregroundStyle(connection.theme.faint)
                .multilineTextAlignment(.center).padding(.horizontal, 20).frame(maxWidth: .infinity)
        case .user:
            VStack(alignment: .trailing, spacing: 3) {
                Text(rendered).font(.callout).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(connection.theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                time
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
        case .godric:
            VStack(alignment: .leading, spacing: 3) {
                Text(rendered).font(.callout).foregroundStyle(connection.theme.text).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if message.hasProposal {
                    Text("Godric drafted a change. Review and apply it on the desktop.")
                        .font(.caption).foregroundStyle(connection.theme.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                time
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 32)
        case .error:
            Text(message.text).font(.callout).foregroundStyle(.red)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.red))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 32)
        }
    }

    @ViewBuilder private var time: some View {
        if let t = message.time {
            Text(Self.clock.string(from: t)).font(.caption2).foregroundStyle(connection.theme.faint).padding(.horizontal, 6)
        }
    }
}

private struct TypingBubble: View {
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in Circle().fill(connection.theme.muted).frame(width: 7, height: 7) }
        }
        .phaseAnimator([0.35, 1.0]) { content, opacity in content.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.6) }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Godric is thinking")
    }
}

private struct HistorySheet: View {
    let model: GodricModel
    let client: APIClient
    @Binding var isPresented: Bool
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        NavigationStack {
            List(model.history) { entry in
                Button {
                    Task { await model.view(entry, client: client); isPresented = false }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title ?? "Untitled conversation").font(.body.weight(.medium)).foregroundStyle(connection.theme.text)
                        Text(subtitle(entry)).font(.caption).foregroundStyle(connection.theme.muted)
                    }
                }
            }
            .overlay { if model.history.isEmpty { Text("No past conversations").foregroundStyle(connection.theme.muted) } }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } } }
        }
        .task { await model.loadHistory(client: client) }
        .presentationDetents([.medium, .large])
    }

    private func subtitle(_ e: HistoryEntry) -> String {
        [e.panel?.capitalized, e.lastActiveAt.map { String($0.prefix(16)) }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The chat input: one reusable piece, with a mic slot beside Send. The slot is present in the layout and the
/// structure but inert in 0.3.0; dictation (0.4.0) fills it without reshaping the component.
/// The book Godric is asked about when chat is opened from Book Details.
struct ChatBook: Equatable { let id: Int; let title: String }

struct ChatInput<Mic: View>: View {
    @Binding var text: String
    var canSend: Bool
    var placeholder: String
    var mic: Mic
    let onSend: () -> Void
    @Environment(ConnectionModel.self) private var connection

    init(text: Binding<String>, canSend: Bool, placeholder: String,
         @ViewBuilder mic: () -> Mic, onSend: @escaping () -> Void) {
        _text = text; self.canSend = canSend; self.placeholder = placeholder; self.mic = mic(); self.onSend = onSend
    }

    private var sendable: Bool { canSend && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .submitLabel(.send)
                .padding(.vertical, 8).padding(.leading, 6)
                // Return sends; Shift-Return keeps a new line.
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    if sendable { onSend() }
                    return .handled
                }
            mic
            Button(action: onSend) { Image(systemName: "arrow.up").font(.body.weight(.bold)).padding(8) }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .disabled(!sendable)
                .accessibilityLabel("Send")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

extension ChatInput where Mic == InertMicSlot {
    init(text: Binding<String>, canSend: Bool, placeholder: String, onSend: @escaping () -> Void) {
        self.init(text: text, canSend: canSend, placeholder: placeholder, mic: { InertMicSlot() }, onSend: onSend)
    }
}

/// The reserved microphone control. Visibly disabled; nothing sits behind it.
struct InertMicSlot: View {
    var body: some View {
        Image(systemName: "mic").font(.body).padding(8)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Dictation, coming later")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Not available yet")
    }
}
