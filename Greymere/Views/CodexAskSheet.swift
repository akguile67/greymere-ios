import SwiftUI

/// Ask the Codex a question. Godric reads the whole Codex and answers, citing the entries he drew on; each citation
/// opens that entry.
struct CodexAskSheet: View {
    @Bindable var model: CodexModel
    var open: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    @State private var question = ""
    @State private var answer: CodexAnswer?
    @State private var asked = ""
    @State private var busy = false
    @State private var message: String?
    @FocusState private var focused: Bool

    private var theme: ThemeStore { connection.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask about your Codex…", text: $question, axis: .vertical).lineLimit(1...5).focused($focused).submitLabel(.send)
                            .onSubmit { Task { await ask() } }
                            .padding(.horizontal, 14).padding(.vertical, 12).glassEffect(.regular, in: .rect(cornerRadius: 18))
                        Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(theme.accent) }
                            .buttonStyle(.plain).disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Ask")
                    }
                    if busy { HStack { ProgressView(); Text("Godric is reading the Codex…").foregroundStyle(theme.muted) } }
                    if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                    if let answer { answerView(answer) }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Ask the Codex").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { focused = true }
    }

    private func answerView(_ a: CodexAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(asked).font(.footnote).foregroundStyle(theme.muted)
            CodexBody(text: readable(a.answer)).frame(maxWidth: .infinity, alignment: .leading).padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
            if a.truncated == true { Text("The answer was cut short. Try a narrower question.").font(.caption).foregroundStyle(.orange) }
            let ids = (a.citedEntryIds ?? []).filter { model.entry($0) != nil }
            if !ids.isEmpty {
                Text("Sources").font(.footnote).foregroundStyle(theme.muted)
                CodexFlow {
                    ForEach(ids, id: \.self) { id in
                        Button { open(id) } label: {
                            Label(model.entry(id)?.name ?? "Entry \(id)", systemImage: model.entry(id)?.type.symbol ?? "book")
                                .font(.footnote).foregroundStyle(theme.accent).padding(.horizontal, 10).padding(.vertical, 5)
                                .glassEffect(.regular.tint(theme.accent.opacity(0.18)).interactive(), in: .capsule)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// "[Entry 123]" becomes the entry's name, so the answer reads as prose; the chips below open them.
    private func readable(_ text: String) -> String {
        var out = text
        let rx = try? NSRegularExpression(pattern: "\\[Entry (\\d+)\\]")
        let ns = out as NSString
        for m in (rx?.matches(in: out, range: NSRange(location: 0, length: ns.length)) ?? []).reversed() {
            let id = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let name = model.entry(id)?.name ?? "entry \(id)"
            out = (out as NSString).replacingCharacters(in: m.range, with: "(\(name))")
        }
        return out
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        busy = true; message = nil; answer = nil; focused = false
        switch await model.ask(q) {
        case .success(let a): answer = a; asked = q; question = ""
        case .failure(let f): message = f.text
        }
        busy = false
    }
}
