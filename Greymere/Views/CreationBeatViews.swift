import SwiftUI

// MARK: one beat

struct BeatCard: View {
    let model: CreationModel
    let beat: CreationBeat
    let edit: () -> Void
    let refs: (String?) -> Void
    let fixBrief: () -> Void
    @Environment(ConnectionModel.self) private var connection
    @State private var confirmDelete = false
    @State private var proposalOpen = true

    private var busy: Bool { model.busyBeats.contains(beat.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(beat.number.map { "BEAT \($0)" } ?? "BEAT").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(connection.theme.muted)
                Text(model.placeLabel(beat)).font(.caption).foregroundStyle(connection.theme.faint).lineLimit(2)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Button { Task { await model.move(beat, by: -1) } } label: { Image(systemName: "arrow.up").padding(6) }
                        .disabled(!model.canMove(beat, by: -1) || model.working).accessibilityLabel("Move beat up")
                    Button { Task { await model.move(beat, by: 1) } } label: { Image(systemName: "arrow.down").padding(6) }
                        .disabled(!model.canMove(beat, by: 1) || model.working).accessibilityLabel("Move beat down")
                }
                .buttonStyle(.plain).foregroundStyle(connection.theme.muted)
                Menu {
                    Button { edit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { Task { await model.move(beat, by: -1) } } label: { Label("Move up", systemImage: "arrow.up") }
                        .disabled(!model.canMove(beat, by: -1))
                    Button { Task { await model.move(beat, by: 1) } } label: { Label("Move down", systemImage: "arrow.down") }
                        .disabled(!model.canMove(beat, by: 1))
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(connection.theme.muted).padding(4)
                }
                .accessibilityLabel("Beat actions")
            }
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    if beat.whatHappens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("What happens in this beat…").font(.callout).foregroundStyle(connection.theme.faint)
                    } else {
                        Text(beat.whatHappens).font(.callout).foregroundStyle(connection.theme.text).multilineTextAlignment(.leading)
                    }
                    if let t = beat.targetWords { Text("Target \(t.formatted()) words").font(.caption).foregroundStyle(connection.theme.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the beat")

            continuityBlock
            referencesBlock

            stopBlock
            if let draft = beat.proposal, !draft.isEmpty { draftBlock(draft) } else { generateRow }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .confirmationDialog("Delete this beat?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete beat", role: .destructive) { Task { await model.deleteBeat(beat) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing in the chapter changes.")
        }
    }

    // The beat contradicts the chapter brief: the author's call, once per beat. Nothing rewrites the brief.
    @ViewBuilder private var continuityBlock: some View {
        if let c = beat.openContinuity {
            VStack(alignment: .leading, spacing: 6) {
                Label("This beat contradicts the chapter brief", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                Text(c.note ?? "").font(.footnote).foregroundStyle(connection.theme.text)
                HStack(spacing: 8) {
                    Button { Task { await model.acceptContinuity(beat) } } label: { Text("Yes — the story goes this way") }
                        .buttonStyle(.glassProminent)
                    Button("Let me correct the brief") { fixBrief() }.buttonStyle(.glass)
                }
                .font(.footnote).disabled(model.working)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if beat.acceptedContinuity {
            Label("The beat overrides the chapter brief — accepted.", systemImage: "checkmark")
                .font(.caption).foregroundStyle(connection.theme.muted)
        }
    }

    private var referencesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                if busy {
                    HStack(spacing: 5) { ProgressView().controlSize(.mini); Text("Resolving references…").font(.caption) }
                        .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(connection.theme.muted)
                        .background(connection.theme.background, in: Capsule())
                }
                ForEach(beat.activeRefs) { ref in chip(ref) }
                ForEach(beat.dismissed, id: \.self) { name in dismissedChip(name) }
                Button { refs(nil) } label: {
                    Label("Add reference", systemImage: "plus").font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(connection.theme.muted)
                        .overlay(Capsule().strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain)
            }
            Button { Task { await model.proposeRefs(beat) } } label: {
                Label(busy ? "Resolving…" : "Propose references", systemImage: "magnifyingglass").font(.footnote)
            }
            .buttonStyle(.glass)
            .disabled(busy || beat.whatHappens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func chip(_ ref: BeatRef) -> some View {
        let gap = ref.exists == false
        let needsDev = ref.exists != false && ref.needsDevelopment == true
        let color: Color = gap ? .red : (needsDev ? .orange : .green)
        let icon = gap ? "exclamationmark.triangle.fill" : (needsDev ? "hourglass" : "checkmark")
        return Menu {
            if gap {
                Button { refs(ref.name) } label: { Label("Link to an existing entry…", systemImage: "link") }
                Button { Task { await model.dismissRef(beat, name: ref.name, restore: false) } } label: { Label("Dismiss (a walk-on, no entry needed)", systemImage: "minus.circle") }
            }
            Button(role: .destructive) {
                Task { await model.setRefs(beat, beat.shownRefs.filter { $0.id != ref.id }) }
            } label: { Label("Remove", systemImage: "xmark") }
        } label: {
            Label(ref.name, systemImage: icon).font(.caption).labelStyle(.titleAndIcon)
                .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(color)
                .background(color.opacity(0.13), in: Capsule())
        }
        .accessibilityHint(gap ? "No codex entry under this name" : needsDev ? "Still needs development" : "Resolved")
    }

    private func dismissedChip(_ name: String) -> some View {
        Button { Task { await model.dismissRef(beat, name: name, restore: true) } } label: {
            Label(name, systemImage: "arrow.uturn.backward").font(.caption).strikethrough()
                .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(connection.theme.faint)
                .overlay(Capsule().strokeBorder(connection.theme.faint.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), dismissed. Restore")
    }

    private var generating: Bool { model.generating.contains(beat.id) }
    private var canGenerate: Bool {
        !generating && !model.isLocked && !beat.whatHappens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var generateRow: some View {
        HStack(spacing: 10) {
            Button { Task { await model.generate(beat) } } label: {
                Label(generating ? "Drafting…" : "Generate", systemImage: "sparkles").font(.footnote)
            }
            .buttonStyle(.glassProminent).disabled(!canGenerate)
            if generating {
                ProgressView().controlSize(.small)
                Text("This can take about a minute.").font(.caption).foregroundStyle(connection.theme.muted)
            }
        }
    }

    // Generation paused before any prose: the exits the iPad has.
    @ViewBuilder private var stopBlock: some View {
        if let stop = model.stops[beat.id] {
            VStack(alignment: .leading, spacing: 8) {
                Label("Generation stopped", systemImage: "hand.raised.fill").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                Text(stop.message).font(.footnote).foregroundStyle(connection.theme.text)
                if let note = stop.continuity {
                    Text(note).font(.footnote).foregroundStyle(connection.theme.muted)
                    HStack(spacing: 8) {
                        Button("Yes — the story goes this way") { Task { await model.acceptStoppedContinuity(beat) } }.buttonStyle(.glassProminent)
                        Button("Let me correct the brief") { fixBrief() }.buttonStyle(.glass)
                    }
                    .font(.footnote).disabled(model.working)
                }
                ForEach(stop.gaps) { gap in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(gap.name) — " + (gap.reason == "needs_development" ? "has an entry that still needs development" : "no codex entry"))
                            .font(.footnote.weight(.semibold)).foregroundStyle(connection.theme.text)
                        HStack(spacing: 8) {
                            Button("Dismiss — a walk-on") { Task { await model.dismissGap(beat, name: gap.name) } }.buttonStyle(.glass)
                            if gap.reason != "needs_development" {
                                Button("Link to an entry…") { refs(gap.name) }.buttonStyle(.glass)
                            }
                        }
                        .font(.footnote).disabled(model.working)
                    }
                }
                if !stop.gaps.isEmpty {
                    Text("To create or develop an entry, finish it in World & Character on the laptop, then generate again.")
                        .font(.caption).foregroundStyle(connection.theme.muted)
                }
                Button("Close") { model.clearStop(beat) }.font(.footnote).buttonStyle(.plain).foregroundStyle(connection.theme.muted)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func draftBlock(_ draft: String) -> some View {
        let words = draft.split(whereSeparator: \.isWhitespace).count
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { proposalOpen.toggle() } } label: {
                Label("Draft — \(words.formatted()) words. Read it; nothing is in the chapter until you accept.", systemImage: proposalOpen ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(connection.theme.muted).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            if proposalOpen {
                Text(draft).font(.callout).foregroundStyle(connection.theme.text).textSelection(.enabled)
                HStack(spacing: 8) {
                    Button { Task { await model.acceptDraft(beat) } } label: { Label("Accept into the chapter", systemImage: "checkmark") }
                        .buttonStyle(.glassProminent).disabled(model.working || generating || model.isLocked)
                    Button { Task { await model.generate(beat) } } label: { Label(generating ? "Drafting…" : "Regenerate", systemImage: "arrow.clockwise") }
                        .buttonStyle(.glass).disabled(!canGenerate)
                    Button("Discard") { Task { await model.discardDraft(beat) } }
                        .buttonStyle(.glass).disabled(model.working || generating)
                }
                .font(.footnote)
                if generating { HStack { ProgressView().controlSize(.small); Text("This can take about a minute.").font(.caption).foregroundStyle(connection.theme.muted) } }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(connection.theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: add or edit a beat

enum BeatSheetTarget: Identifiable {
    case add
    case edit(CreationBeat)
    var id: String { switch self { case .add: "add"; case .edit(let b): "edit-\(b.id)" } }
}

struct BeatSheet: View {
    let model: CreationModel
    let target: BeatSheetTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    @State private var text = ""
    @State private var targetText = ""
    @State private var inText = false
    @State private var paragraph = 0
    @State private var saving = false

    private var editing: CreationBeat? { if case .edit(let b) = target { b } else { nil } }
    private var paragraphCount: Int { model.paragraphs().count }
    private var targetWords: Int? { Int(targetText.trimmingCharacters(in: .whitespaces)) }
    private var canSave: Bool { !saving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("What happens in this beat") {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
                Section {
                    HStack {
                        Text("Target words")
                        Spacer()
                        TextField("300", text: $targetText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    }
                }
                if editing == nil {
                    Section("Place") {
                        Picker("Place", selection: $inText) {
                            Text("End of chapter").tag(false)
                            Text("In the text").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(paragraphCount == 0)
                        if inText && paragraphCount > 0 {
                            Stepper(value: $paragraph, in: 0...paragraphCount) {
                                Text(paragraph == 0 ? "Before the first paragraph" : "After paragraph \(paragraph)")
                            }
                            if paragraph > 0, paragraph <= paragraphCount {
                                Text(model.paragraphs()[paragraph - 1]).font(.footnote).foregroundStyle(connection.theme.muted).lineLimit(3)
                            }
                        } else if paragraphCount == 0 {
                            Text("The chapter has no prose yet, so the beat goes at the end.").font(.footnote).foregroundStyle(connection.theme.muted)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add beat" : "Edit beat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            .onAppear {
                if let b = editing { text = b.whatHappens; targetText = b.targetWords.map(String.init) ?? "" }
            }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        if let b = editing { ok = await model.updateBeat(b, text: body, target: targetWords) }
        else { ok = await model.addBeat(body, target: targetWords, position: inText && paragraphCount > 0 ? paragraph : nil) }
        if ok { dismiss() }
    }
}

// MARK: references

struct RefsSheet: View {
    let model: CreationModel
    let beatId: Int
    let linking: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    @State private var search = ""
    @State private var custom = ""

    private var beat: CreationBeat? { model.doc?.beats.first { $0.id == beatId } }

    private var matches: [ReferenceCandidate] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.candidates.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let beat, linking == nil {
                    Section("On this beat") {
                        if beat.activeRefs.isEmpty { Text("None").foregroundStyle(connection.theme.muted) }
                        ForEach(beat.shownRefs) { ref in
                            HStack {
                                Text(ref.name)
                                Spacer()
                                Button { Task { await model.setRefs(beat, beat.shownRefs.filter { $0.id != ref.id }) } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(connection.theme.muted)
                                }
                                .buttonStyle(.plain).accessibilityLabel("Remove \(ref.name)")
                            }
                        }
                    }
                    Section("A name not in the codex yet") {
                        HStack {
                            TextField("Name", text: $custom)
                            Button("Add") {
                                let name = custom.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                custom = ""
                                Task { await model.setRefs(beat, beat.shownRefs + [BeatRef(name: name)]) }
                            }
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                Section(linking.map { "Link “\($0)” to" } ?? "Codex entries") {
                    ForEach(matches) { entry in
                        Button { Task { await choose(entry) } } label: {
                            HStack {
                                Text(entry.name).foregroundStyle(connection.theme.text)
                                Spacer()
                                Text(entry.type.capitalized).font(.caption).foregroundStyle(connection.theme.muted)
                            }
                        }
                    }
                    if model.candidates.isEmpty { Text("No codex entries").foregroundStyle(connection.theme.muted) }
                }
            }
            .searchable(text: $search, prompt: "Search the codex")
            .navigationTitle(linking == nil ? "References" : "Link reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { if let beat { await model.loadCandidates(for: beat) } }
        }
    }

    private func choose(_ entry: ReferenceCandidate) async {
        guard let beat else { return }
        if let linking {
            // The gap's name is kept as an alias of the entry by the server; the entry replaces the red chip.
            var list = beat.shownRefs.filter { $0.name.lowercased() != linking.lowercased() }
            list.append(BeatRef(name: linking, codexId: entry.id, type: entry.type))
            await model.setRefs(beat, list)
            dismiss()
        } else {
            guard !beat.shownRefs.contains(where: { $0.name.lowercased() == entry.name.lowercased() }) else { return }
            await model.setRefs(beat, beat.shownRefs + [BeatRef(name: entry.name, codexId: entry.id, type: entry.type)])
        }
    }
}
