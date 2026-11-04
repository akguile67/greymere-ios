import SwiftUI

/// Editing a Codex entry (ADR 0.59.0, decision D1): every edit, typed or dictated, becomes a proposal shown as a
/// marked-up diff, and only Apply writes it. Apply is refused when the entry has changed since the sheet opened.
struct CodexEditSheet: View {
    @Bindable var model: CodexModel
    let client: APIClient
    /// nil = a new entry.
    let id: Int?
    var onCreated: (Int) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    private enum Step { case edit, review }
    @State private var step: Step = .edit
    @State private var name = ""
    @State private var aliasText = ""
    @State private var bodyText = ""
    @State private var selection: TextSelection?
    // What the entry looked like when the edit began (or when last refreshed after a refusal).
    @State private var baseName = ""
    @State private var baseAliases = ""
    @State private var baseBody = ""
    @State private var baseStamp: String?
    @State private var saving = false
    @State private var message: String?
    @State private var dictation = DictationModel()
    @State private var prose = ProseController()
    @State private var newType: CodexType = .characters
    private var isNew: Bool { id == nil }

    private var theme: ThemeStore { connection.theme }
    private var nameChanged: Bool { name.trimmingCharacters(in: .whitespaces) != baseName }
    private var aliasesChanged: Bool { Self.parse(aliasText) != Self.parse(baseAliases) }
    private var bodyChanged: Bool { bodyText != baseBody }
    private var changed: Bool { isNew ? !name.trimmingCharacters(in: .whitespaces).isEmpty : (nameChanged || aliasesChanged || bodyChanged) }

    /// The words with their Markdown marks taken off, for reading what changed.
    private static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "(?m)^#{1,6}[ \\t]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*+", with: "", options: .regularExpression)
    }

    private static func parse(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            Group { if step == .edit { editor } else { review } }
                .background(theme.background.ignoresSafeArea())
                .navigationTitle(step == .edit ? (isNew ? "New entry" : "Edit entry") : (isNew ? "Review the new entry" : "Review the change"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(step == .edit ? "Cancel" : "Back") { if step == .edit { dictation.end(); dismiss() } else { step = .edit } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if step == .edit { Button("Review") { dictation.settle(); dictation.end(); message = nil; step = .review }.disabled(!changed) }
                        else { Button(saving ? "Applying…" : "Apply") { Task { await apply() } }.disabled(!changed || saving) }
                    }
                }
        }
        .onAppear(perform: load)
        .task(id: connection.address) { await dictation.check(client: client) }
        .onChange(of: bodyText) { _, new in dictation.textChanged(to: new) }
        .onDisappear { dictation.settle(); dictation.end() }
    }

    private func load() {
        guard baseStamp == nil else { return }
        guard let id else { baseStamp = ""; return }
        guard let d = model.details[id], let e = model.entry(id) else { return }
        fill(name: d.name, aliases: d.aliases ?? e.allAliases, body: d.body ?? e.snippet, stamp: d.updatedAt, keepDrafts: false)
    }

    private func fill(name n: String, aliases: [String], body b: String, stamp: String?, keepDrafts: Bool) {
        baseName = n; baseAliases = aliases.joined(separator: ", "); baseBody = b; baseStamp = stamp ?? ""
        if !keepDrafts { name = n; aliasText = baseAliases; bodyText = b }
    }

    // MARK: step 1, edit

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isNew {
                    field("Type") {
                        Picker("Type", selection: $newType) { ForEach(CodexType.allCases) { Text($0.single).tag($0) } }
                            .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                field("Name") { TextField("Name", text: $name).textInputAutocapitalization(.words) }
                field("Also known as (separate with commas)") { TextField("Aliases", text: $aliasText, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Body").font(.footnote).foregroundStyle(theme.muted)
                    // The manuscript's own editor: bold and italic show as bold and italic, the markers are hidden until the
                    // caret touches them.
                    ProseTextView(text: $bodyText, selection: $selection, editable: true,
                                  headings: true, hideKeyboard: dictation.state == .listening || dictation.state == .starting,
                                  trailingBreak: false, controller: prose)
                        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                        .padding(10).glassEffect(.regular, in: .rect(cornerRadius: 16))
                    if let notice = dictation.notice { Text(notice).font(.caption).foregroundStyle(.orange).onTapGesture { dictation.notice = nil } }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        // Pinned above the keyboard (or the bottom edge), so it is in reach while you edit however long the body is.
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    formatButton("bold", "Bold") { prose.format(.bold) }
                    formatButton("italic", "Italic") { prose.format(.italic) }
                    micButton
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(theme.muted)
            content().padding(.horizontal, 14).padding(.vertical, 12).glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private func formatButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(theme.text)
                .frame(width: 40, height: 32).glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var micButton: some View {
        let listening = dictation.state == .listening
        let working = dictation.state == .starting || dictation.state == .stopping
        return Button {
            Task { await dictation.toggle(client: client, bookId: nil, field: DictationField(text: $bodyText, selection: $selection)) }
        } label: {
            Label(listening ? "Stop" : "Dictate", systemImage: dictation.available == false ? "mic.slash" : (listening ? "mic.fill" : "mic"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(listening ? AnyShapeStyle(Color.red) : AnyShapeStyle(theme.accent))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain).disabled(working || dictation.available == false)
    }

    // MARK: step 2, review

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message { Text(message).font(.footnote).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 14)) }
                if !changed { Text("Nothing has changed.").foregroundStyle(theme.muted) }
                if isNew { Text("Type: \(newType.single)").font(.footnote).foregroundStyle(theme.muted) }
                if nameChanged { block("Name", before: baseName, after: name.trimmingCharacters(in: .whitespaces)) }
                if aliasesChanged { block("Also known as", before: baseAliases, after: Self.parse(aliasText).joined(separator: ", ")) }
                if bodyChanged {
                    let b = Self.plain(baseBody), a = Self.plain(bodyText)
                    if a == b { Text("Body: formatting only (bold, italic or headings), no words changed.").font(.footnote).foregroundStyle(theme.muted) }
                    else { block("Body: words changed", before: b, after: a) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How the body will read").font(.footnote).foregroundStyle(theme.muted)
                        CodexBody(text: bodyText).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    }
                }
                Text("Apply writes this to the Codex. If the entry changed elsewhere since you started, nothing is written and you can review again.")
                    .font(.caption).foregroundStyle(theme.faint)
            }
            .padding()
        }
    }

    private func block(_ title: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(theme.muted)
            Text(DiffText.marked(before: before, after: after, theme: theme))
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: Apply

    private func apply() async {
        saving = true; defer { saving = false }
        guard let id else {
            if let newId = await model.create(name: name.trimmingCharacters(in: .whitespaces), type: newType, aliases: Self.parse(aliasText), body: bodyText, client: client) { dismiss(); onCreated(newId) }
            else { message = "The entry could not be created." }
            return
        }
        let result = await model.apply(id: id, name: name.trimmingCharacters(in: .whitespaces), aliases: Self.parse(aliasText), body: bodyText, baseStamp: baseStamp ?? "", client: client)
        switch result {
        case .saved: dismiss()
        case .stale(let d):
            // Keep what was typed, but compare it with the entry as it is now.
            fill(name: d.name, aliases: d.aliases ?? [], body: d.body ?? "", stamp: d.updatedAt, keepDrafts: true)
            message = "This entry changed since you opened it, so nothing was written. The marked-up change below is now against the current version. Check it, then Apply again."
        case .failed(let text): message = text
        }
    }
}
