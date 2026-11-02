import SwiftUI

/// The Creation panel: pick a chapter of the active book, then its brief, its beats and Godric on call. The shape is the
/// Ideation panel's: on iPad Godric docks beside the chapter, on iPhone he rises as a sheet over it. Prose, drafting
/// and Lock are not in the app yet (ADR 0.55.0, Sprint 3).
struct CreationScreen: View {
    @Bindable var model: CreationModel
    let home: HomeModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("greymere.activeBookId") private var activeBookId = 0
    @State private var chatOpen = false
    @AppStorage("greymere.godricWidth") private var godricWidth = 400.0

    private var docked: Bool { sizeClass == .regular }
    private var chatBook: ChatBook? {
        guard model.chapterId != nil, let doc = model.doc, let book = doc.book else { return nil }
        return ChatBook(id: book.id, title: book.title)
    }

    /// The chapter's actions always sit in the glass bar's row; an upright phone shrinks Ask Godric to his sparkle to make room.
    private var inlineBar: Bool { true }

    /// On a phone on its side the chapter's actions go into the glass bar's own row.
    private var inlineActions: AnyView? {
        guard inlineBar, model.chapterId != nil, model.doc != nil else { return nil }
        return AnyView(ChapterActions(model: model))
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Group {
                    if model.chapterId == nil { CreationPicker(model: model, client: client) }
                    else { CreationChapterView(model: model, client: client) }
                }
                if docked && chatOpen, let chatBook {
                    DockHandle(width: $godricWidth, available: geo.size.width)
                    GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                        .frame(width: min(max(godricWidth, 220), max(240, geo.size.width - 300)))
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.snappy, value: chatOpen)
        .background(connection.theme.background.ignoresSafeArea())
        .topBand(true, title: "Creation")
        .glassBar(isOpen: chatOpen, inline: inlineActions) {
            if model.chapterId != nil { chatOpen.toggle() }
            else { model.banner = .init(text: "Open a chapter to talk to Godric about its beats.") }
        }
        .sheet(isPresented: Binding(get: { chatOpen && !docked }, set: { chatOpen = $0 })) {
            if let chatBook {
                GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .task { await model.loadBooks(client: client, preferred: activeBookId) }
        .onChange(of: model.chapterId) { _, id in if id == nil { chatOpen = false } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refreshOnForeground() } } }
        .onDisappear { Task { await model.close() } }
    }
}

// MARK: picker

private struct CreationPicker: View {
    @Bindable var model: CreationModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @AppStorage("greymere.activeBookId") private var activeBookId = 0

    private var currentTitle: String { model.books.first { $0.id == model.bookId }?.title ?? model.bookDoc?.book.title ?? "Choose a book" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let banner = model.banner { BannerView(banner: banner) { model.banner = nil } }
                if let error = model.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(connection.theme.muted)
                        Button("Try again") { Task { await model.loadBooks(client: client, preferred: activeBookId) } }.buttonStyle(.glass)
                    }
                } else if let doc = model.bookDoc {
                    if !doc.acts.contains(where: { $0.chapters.contains { $0.briefed == true } }) {
                        Text("No briefed chapters yet for \(doc.book.title). Brief a chapter in Structure on the laptop, then come back to draft it.")
                            .foregroundStyle(connection.theme.muted)
                    } else {
                        let badges = CreationModel.badges(doc.acts)
                        ForEach(doc.acts) { act in actGroup(act, badges: badges) }
                    }
                } else if model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if model.books.isEmpty {
                    Text("No books are ready for Creation.").foregroundStyle(connection.theme.muted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await model.reloadBook() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(model.books) { book in
                    Button {
                        activeBookId = book.id
                        Task { await model.selectBook(book.id, client: client) }
                    } label: {
                        if book.id == model.bookId { Label(book.title, systemImage: "checkmark") } else { Text(book.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentTitle).font(.serif(24))
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(connection.theme.text)
            }
            .disabled(model.books.isEmpty)
            .accessibilityLabel("Book: \(currentTitle). Change book")
            Text("Pick a chapter to read its brief and agree its beats.").font(.caption).foregroundStyle(connection.theme.faint)
        }
    }

    private func actGroup(_ act: CreationAct, badges: [Int: String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(act.title ?? "Act").font(.subheadline.weight(.semibold)).foregroundStyle(connection.theme.text)
                Spacer(minLength: 8)
                Text("\(act.draftOneCount ?? 0)/\(act.chapters.count) drafted · \(act.briefedCount ?? 0) briefed")
                    .font(.caption).foregroundStyle(connection.theme.faint)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(act.chapters) { ch in card(ch, badge: badges[ch.id] ?? "Ch \(ch.number ?? 0)") }
            }
        }
    }

    private func card(_ ch: CreationChapterCard, badge: String) -> some View {
        let canOpen = ch.canDraft == true
        let beats = (ch.beatCount ?? 0) > 0 ? "\(ch.beatCount!) beat\(ch.beatCount == 1 ? "" : "s")" : nil
        let words = (ch.wordCount ?? 0) > 0 ? "\(ch.wordCount!.formatted()) words" : nil
        let meta = [beats, words].compactMap { $0 }.joined(separator: " · ")
        return Button { Task { await model.open(ch.id, client: client) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(badge).font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
                    Spacer(minLength: 6)
                    if let w = ch.codexWarning, !w.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Codex gap: \(w.map(\.name).joined(separator: ", "))")
                    }
                    StatusChip(status: ch.creationStatus, briefed: ch.briefed)
                }
                Text(ch.title ?? "Untitled").font(.body.weight(.medium)).foregroundStyle(connection.theme.text)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(connection.theme.muted) }
                if !canOpen { Text("Brief in Structure first").font(.caption).foregroundStyle(connection.theme.faint) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(canOpen ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }
}

// MARK: shared pieces

struct StatusChip: View {
    let status: String?
    var briefed: Bool? = true
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        let color: Color = switch status {
        case "draft_one": .green
        case "drafting": .orange
        default: briefed == false ? connection.theme.faint : connection.theme.accent
        }
        Text(CreationModel.statusLabel(status, briefed: briefed))
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct BannerView: View {
    let banner: CreationModel.Banner
    let dismiss: () -> Void
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        HStack(alignment: .top) {
            Text(banner.text).font(.footnote).foregroundStyle(banner.isError ? Color.red : connection.theme.text)
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(banner.isError ? Color.red : connection.theme.faint.opacity(0.5)))
    }
}

// MARK: chapter

private struct CreationChapterView: View {
    @Bindable var model: CreationModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var briefOpen = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var refsFor: RefsTarget?
    @State private var confirmLeave = false
    @State private var dictation = DictationModel()
    @State private var activeSeg: Int?
    @State private var selection: TextSelection?
    @State private var openEmpty: Set<Int> = []
    @State private var focusSeg: Int?
    @State private var composingQuote: String?
    @State private var showNotes = false
    @State private var confirmLock = false
    @State private var confirmUnlock = false
    @State private var prose = ProseController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            // Pinned, so the way back to the chapter list is always on screen.
            HStack {
                Button { if model.briefEditing { confirmLeave = true } else { Task { await model.close() } } } label: {
                    // On a phone, with the formatting buttons showing, the way back is the arrow alone.
                    if sizeClass == .compact && activeSeg != nil && !model.isLocked {
                        Image(systemName: "chevron.backward").font(.subheadline.weight(.semibold)).padding(.horizontal, 2)
                    } else {
                        Label("Chapters", systemImage: "chevron.backward").font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.glass).accessibilityLabel("Chapters")
                Spacer(minLength: 6)
                if model.doc != nil { textTools }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let banner = model.banner { BannerView(banner: banner) { model.banner = nil } }
                    if let p = model.proposal, p.pending { proposalCard(p) }
                    if model.opening && model.doc == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let error = model.openError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).foregroundStyle(connection.theme.muted)
                            if let id = model.chapterId { Button("Try again") { Task { await model.open(id, client: client) } }.buttonStyle(.glass) }
                        }
                    } else if model.doc != nil {
                        briefSection
                        flowSection
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refreshOnForeground() }
            actions
        }
        .confirmationDialog("Discard your changes to the brief?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Discard and leave", role: .destructive) { Task { await model.close() } }
            Button("Keep editing", role: .cancel) {}
        }
        .task(id: client.baseURL) { await dictation.check(client: client) }
        .onChange(of: activeText) { _, new in dictation.textChanged(to: new) }
        .onChange(of: dictation.state) { old, new in if old == .listening || old == .stopping, new == .idle { dismissKeyboard() } }
        .onChange(of: activeSeg) { dictation.settle(); dictation.end() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dictation.settle(); dictation.end() } }
        .onDisappear { dictation.settle(); dictation.end() }
        .sheet(item: $model.beatSheet) { target in BeatSheet(model: model, target: target) }
        .sheet(item: $model.conflict) { c in ProseConflictSheet(model: model, conflict: c) }
        .sheet(isPresented: Binding(get: { composingQuote != nil }, set: { if !$0 { composingQuote = nil } })) {
            NoteComposer(model: model, quote: composingQuote ?? "") { composingQuote = nil }
        }
        .sheet(isPresented: $showNotes) { NotesSheet(model: model) }
        .confirmationDialog("Lock this chapter as draft one?", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Lock as draft one") { Task { await model.lockDraft() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lockMessage)
        }
        .sheet(item: $refsFor) { target in RefsSheet(model: model, beatId: target.beatId, linking: target.linking) }
    }

    private var header: some View {
        let ch = model.doc?.chapter
        let badge = model.bookDoc.flatMap { CreationModel.badges($0.acts)[model.chapterId ?? 0] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let badge { Text(badge).font(.subheadline.weight(.semibold)).foregroundStyle(connection.theme.muted) }
                Text(ch?.title ?? "Chapter").font(.serif(24)).foregroundStyle(connection.theme.text)
            }
            if let ch {
                HStack(spacing: 8) {
                    StatusChip(status: ch.creationStatus)
                    if ch.creationStatus == "draft_one" { Text("Draft one — locked").font(.caption).foregroundStyle(connection.theme.muted) }
                    if let words = model.doc?.prose?.wordCount, words > 0 {
                        Text("\(words.formatted()) words").font(.caption).foregroundStyle(connection.theme.faint)
                    }
                    if model.dirty {
                        Label("Unsaved edits", systemImage: "circle.fill").labelStyle(.titleAndIcon).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 8)
                    if ch.creationStatus != "draft_one", !model.isLocked {
                        Button { confirmLock = true } label: { Label(model.locking ? "Locking…" : "Lock as draft one", systemImage: "lock").font(.footnote) }
                            .buttonStyle(.glass).disabled(model.locking || model.working || model.doc?.prose?.wordCount ?? 0 == 0)
                    }
                }
            }
        }
    }

    // MARK: brief

    private var briefSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation(.snappy) { briefOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).rotationEffect(.degrees(briefOpen ? 90 : 0))
                        Text("BRIEF").font(.caption.weight(.semibold)).tracking(0.8)
                    }
                    .foregroundStyle(connection.theme.muted)
                }
                .buttonStyle(.plain).accessibilityLabel(briefOpen ? "Collapse the brief" : "Expand the brief")
                Spacer()
                if briefOpen {
                    if model.briefEditing {
                        Button("Cancel") { model.cancelBriefEdit() }.buttonStyle(.glass)
                        Button { Task { await model.saveBrief() } } label: { Label("Save brief", systemImage: "checkmark") }
                            .buttonStyle(.glassProminent).disabled(model.working)
                    } else {
                        Button { model.beginBriefEdit() } label: { Label("Edit", systemImage: "pencil") }.buttonStyle(.glass)
                    }
                }
            }
            .font(.subheadline)
            if briefOpen {
                if model.briefEditing {
                    briefEditor("Setting", \.setting)
                    briefEditor("Who is in this chapter", \.who)
                    briefEditor("What happens", \.whatHappens)
                    briefEditor("What the reader learns", \.readerLearns)
                    briefEditor("What the chapter achieves", \.achieves)
                } else {
                    briefRead("Setting", model.brief.setting)
                    briefRead("Who is in this chapter", model.brief.who)
                    briefRead("What happens", model.brief.whatHappens)
                    briefRead("What the reader learns", model.brief.readerLearns)
                    briefRead("What the chapter achieves", model.brief.achieves)
                }
            }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func briefRead(_ label: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text).font(.callout).foregroundStyle(connection.theme.text).textSelection(.enabled)
            } else {
                Text("—").font(.callout).foregroundStyle(connection.theme.faint)
            }
        }
    }

    private func briefEditor(_ label: String, _ key: WritableKeyPath<CreationBrief, String?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
            TextEditor(text: Binding(get: { model.briefDraft[keyPath: key] ?? "" }, set: { model.briefDraft[keyPath: key] = $0 }))
                .font(.callout).scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(6)
                .background(connection.theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: beats

    private var activeText: String {
        guard let i = activeSeg, model.segmentsShown.indices.contains(i) else { return "" }
        return model.segmentsShown[i]
    }

    private var lockMessage: String {
        let n = model.openNotes.count
        let pending = model.doc?.beats.count ?? 0
        var parts = ["The chapter is marked draft one and becomes eligible for the editing tower. The prose is already the manuscript; nothing is rebuilt."]
        if pending > 0 { parts.append("\(pending) pending beat\(pending == 1 ? "" : "s") will stay on the chapter.") }
        if n > 0 { parts.append("You have \(n) drafting note\(n == 1 ? "" : "s") in this chapter. You may want to look at \(n == 1 ? "it" : "them") first. They have to be cleared before the book goes to Editing.") }
        return parts.joined(separator: "\n\n")
    }

    // MARK: the chapter: its text with each pending beat's card between the passages

    private var flowSection: some View {
        let beats = model.doc?.beats ?? []
        let segs = model.segmentsShown
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("CHAPTER").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(connection.theme.muted)
            }
            if model.lockApplies { lockBar }
            if let notice = dictation.notice {
                Text(notice).font(.caption).foregroundStyle(connection.theme.muted).onTapGesture { dictation.notice = nil }
            }
            if !dictation.chips.isEmpty { chipStrip }
            if segs.count == beats.count + 1 {
                ForEach(0...beats.count, id: \.self) { i in
                    segmentView(i, of: segs)
                    if i < beats.count {
                        BeatCard(model: model, beat: beats[i],
                                 edit: { model.beatSheet = .edit(beats[i]) },
                                 refs: { linking in refsFor = RefsTarget(beatId: beats[i].id, linking: linking) },
                                 fixBrief: { briefOpen = true; model.beginBriefEdit() })
                    }
                }
            } else {
                Text("The chapter couldn't be laid out. Pull down to read it again.").font(.footnote).foregroundStyle(connection.theme.muted)
            }
            if beats.isEmpty, (segs.first ?? "").isEmpty {
                Text("Nothing here yet. Write, dictate, or add a beat and generate it.").font(.subheadline).foregroundStyle(connection.theme.muted)
            }
        }
    }

    private var lockBar: some View {
        let number = "This chapter"
        return VStack(alignment: .leading, spacing: 8) {
            if model.isLocked {
                Label("\(number) is locked. The book is past editing, so its text is kept in step with the assembled files.", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(connection.theme.text)
                Button { confirmUnlock = true } label: { Label(model.unlocking ? "Unlocking…" : "Unlock to change…", systemImage: "lock.open").font(.footnote) }
                    .buttonStyle(.glass).disabled(model.unlocking || model.working)
            } else {
                Label("\(number) is unlocked for changes. Its files may need regenerating and re-uploading afterwards.", systemImage: "lock.open.fill")
                    .font(.footnote).foregroundStyle(connection.theme.text)
                Button { Task { dismissKeyboard(); await model.setChapterLock(true) } } label: { Label(model.unlocking ? "Locking…" : "Lock again", systemImage: "lock").font(.footnote) }
                    .buttonStyle(.glass).disabled(model.unlocking || model.working || model.savingProse)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog("Unlock this chapter for changes?", isPresented: $confirmUnlock, titleVisibility: .visible) {
            Button("Unlock chapter", role: .destructive) { Task { await model.setChapterLock(false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.unlockWarning + "\n\nUnlock it only if the text really has to change.")
        }
    }

    /// Bold, Italic and Scene break for the prose segment being edited. Pressing one does not take focus from it.
    private var formatTools: some View {
        HStack(spacing: 4) {
            Button { prose.format(.bold) } label: { Image(systemName: "bold").padding(2) }.accessibilityLabel("Bold")
            Button { prose.format(.italic) } label: { Image(systemName: "italic").padding(2) }.accessibilityLabel("Italic")
            Button { prose.format(.sceneBreak) } label: { Image(systemName: "ellipsis").padding(2) }.accessibilityLabel("Scene break")
        }
        .buttonStyle(.glass)
    }

    private var textTools: some View {
        HStack(spacing: 6) {
            if activeSeg != nil && !model.isLocked { formatTools }
            Button { Task { await toggleDictation() } } label: {
                Image(systemName: dictation.state == .listening ? "mic.fill" : (dictation.available == false ? "mic.slash" : "mic"))
                    .foregroundStyle(dictation.state == .listening ? Color.red : connection.theme.text)
                    .symbolEffect(.pulse, isActive: dictation.state == .listening).padding(4)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .disabled(model.isLocked || dictation.state == .starting || dictation.state == .stopping)
            .accessibilityLabel(dictation.state == .listening ? "Stop dictation" : "Dictate into the text")
            Button {
                if let q = model.noteQuote { composingQuote = q }
                else { model.banner = .init(text: "Select the passage you want to leave a note about, then press Note.") }
            } label: {
                if sizeClass == .compact { Image(systemName: "note.text").padding(2) } else { Label("Note", systemImage: "note.text").font(.footnote) }
            }
            .buttonStyle(.glass).accessibilityLabel("Add a note to the selected passage")
            Button { showNotes = true } label: {
                if sizeClass == .compact {
                    Image(systemName: "list.bullet").padding(2).overlay(alignment: .topTrailing) {
                        if !model.openNotes.isEmpty { Text("\(model.openNotes.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(3).background(Color.orange, in: Circle()).offset(x: 8, y: -8) }
                    }
                } else {
                    Label("Notes" + (model.openNotes.isEmpty ? "" : " (\(model.openNotes.count))"), systemImage: "list.bullet").font(.footnote)
                }
            }
            .buttonStyle(.glass).accessibilityLabel("Drafting notes")
        }
    }

    private var chipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dictation.chips) { chip in
                    Button { dictation.act(on: chip) } label: {
                        Text(chip.label).font(.footnote).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(connection.theme.muted).background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleDictation() async {
        guard let i = activeSeg, model.segmentsShown.indices.contains(i) else {
            model.banner = .init(text: "Tap in the text where you want the words to go, then press the microphone.")
            return
        }
        let field = DictationField(
            text: Binding(get: { model.segmentsShown.indices.contains(i) ? model.segmentsShown[i] : "" }, set: { model.setSegment(i, $0) }),
            selection: $selection)
        await dictation.toggle(client: client, bookId: model.doc?.book?.id, field: field)
    }

    @ViewBuilder private func segmentView(_ i: Int, of segs: [String]) -> some View {
        let text = segs[i]
        if text.isEmpty && !openEmpty.contains(i) && activeSeg != i {
            if !model.isLocked {
                Button { openEmpty.insert(i); focusSeg = i } label: {
                    Label("Write here", systemImage: "plus").font(.caption).foregroundStyle(connection.theme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain)
            }
        } else {
            ProseTextView(
                text: Binding(get: { model.segmentsShown.indices.contains(i) ? model.segmentsShown[i] : "" }, set: { model.setSegment(i, $0) }),
                selection: activeSeg == i ? $selection : .constant(nil),
                editable: !model.isLocked,
                highlights: model.openNotes.compactMap(\.anchorQuote),
                focusOnAppear: focusSeg == i,
                hideKeyboard: activeSeg == i && (dictation.state == .listening || dictation.state == .starting),
                trailingBreak: i < segs.count - 1,
                controller: prose,
                onFocus: { activeSeg = i; selection = nil; if focusSeg == i { focusSeg = nil } },
                onSelectedQuote: { q in if activeSeg == i || q != nil { model.noteQuote = q } })
                .padding(.horizontal, 6)
                .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Godric's drafted change

    private func proposalCard(_ p: BeatProposalCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Drafted beat change: not applied yet", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
            Text("Read it through. The beat stays as it is until you press Apply, here or in the bar at the bottom.")
                .font(.footnote).foregroundStyle(connection.theme.muted)
            if let n = p.beat?.number { Text("Beat \(n)").font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted) }
            if let r = p.reason, !r.isEmpty { Text(r).font(.footnote).foregroundStyle(connection.theme.muted) }
            VStack(alignment: .leading, spacing: 6) {
                if p.currentBody.isEmpty {
                    Text("NEW BEAT").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    Text(p.proposedBody).font(.footnote).foregroundStyle(connection.theme.text)
                } else {
                    Text("CHANGED").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    Text(DiffText.marked(before: p.currentBody, after: p.proposedBody, theme: connection.theme))
                        .font(.footnote).foregroundStyle(connection.theme.text)
                }
                if let b = p.beat, b.currentTargetWords != b.proposedTargetWords {
                    Text("Target words: \(b.currentTargetWords.map(String.init) ?? "none") → \(b.proposedTargetWords.map(String.init) ?? "none")")
                        .font(.caption).foregroundStyle(connection.theme.muted)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(connection.theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 10) {
                Button { Task { await model.applyProposal() } } label: { Label("Apply", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).disabled(model.working || model.isLocked)
                Button("Discard") { Task { await model.discardProposal() } }.buttonStyle(.glass).disabled(model.working)
            }
            if model.isLocked { Text(CreationModel.lockedWords).font(.caption).foregroundStyle(connection.theme.muted) }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.6)))
    }

    // MARK: bottom bar

    @ViewBuilder private var actions: some View {
        EmptyView()
    }
}

/// The chapter's bottom actions: Apply or Discard a drafted beat change, Save or Discard edits, Add beat and Undo.
/// On a phone on its side they are set into the glass bar instead of a row of their own.
struct ChapterActions: View {
    @Bindable var model: CreationModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var tight: Bool { verticalSizeClass == .compact }

    var body: some View {
        HStack(spacing: 12) {
            if let p = model.proposal, p.pending {
                GlassPill(title: tight ? "Apply" : "Apply change", systemImage: "checkmark", prominent: true, label: "Apply drafted change") {
                    Task { await model.applyProposal() }
                }
                .disabled(model.working || model.isLocked)
                GlassPill(title: "Discard", label: "Discard drafted change") { Task { await model.discardProposal() } }
                    .disabled(model.working)
            } else if model.dirty {
                GlassPill(title: model.savingProse ? "Saving…" : "Save", systemImage: "checkmark", prominent: true) {
                    dismissKeyboard()
                    Task { await model.saveProse() }
                }
                .disabled(model.savingProse)
                GlassPill(title: "Discard", label: "Discard edits") { model.discardEdits() }.disabled(model.savingProse)
            } else {
                if !model.isLocked {
                    GlassPill(title: "Add beat", systemImage: "plus", prominent: true) { model.beatSheet = .add }
                        .disabled(model.doc == nil || model.working)
                }
                if model.lastAccept != nil, !model.isLocked {
                    GlassPill(systemImage: "arrow.uturn.backward", label: "Undo last draft") { Task { await model.undoLastDraft() } }
                        .disabled(model.working)
                }
            }
        }
    }
}

// MARK: conflict and notes

/// The chapter changed elsewhere since it was opened (or its beats did): what the author typed beside the text now.
struct ProseConflictSheet: View {
    let model: CreationModel
    let conflict: ProseConflict
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
            ScrollView { Text(text.isEmpty ? "—" : text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .padding(8).frame(maxHeight: 220)
                .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(connection.theme.muted).frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(conflict.kind == .changed
                         ? "This chapter was saved from somewhere else after you opened it, so what you typed on this device has not been saved. Nothing has been overwritten."
                         : "The beats on this chapter were changed from somewhere else, so nothing was saved from this device.")
                        .font(.subheadline)
                    block("This device (not saved)", conflict.mine)
                    if conflict.kind == .changed { block("The saved chapter", conflict.theirs) }
                    VStack(alignment: .leading, spacing: 14) {
                        if conflict.kind == .changed {
                            VStack(alignment: .leading, spacing: 6) {
                                Button { Task { await model.keepMine(); dismiss() } } label: { Text("Keep this device's version").frame(maxWidth: .infinity) }
                                    .buttonStyle(.glassProminent)
                                caption("Replaces the saved chapter with this device's text. The saved version is kept in Version history.")
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                UIPasteboard.general.string = conflict.mine
                                Task { await model.useCurrent(); dismiss() }
                            } label: { Text(conflict.kind == .changed ? "Take the saved version" : "Take the saved chapter").frame(maxWidth: .infinity) }
                                .buttonStyle(.glass)
                            caption(conflict.kind == .changed
                                    ? "Discards what you typed on this device and loads the saved chapter. Your typing is copied to the clipboard first."
                                    : "Loads the saved chapter. What you typed on this device is copied to the clipboard first.")
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("The chapter changed").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not yet") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

struct NoteComposer: View {
    let model: CreationModel
    let quote: String
    let done: () -> Void
    @Environment(ConnectionModel.self) private var connection
    @State private var text = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("The passage") { Text("“\(quote.prefix(300))”").font(.footnote).foregroundStyle(connection.theme.muted) }
                Section("Your note") { TextEditor(text: $text).frame(minHeight: 120) }
            }
            .navigationTitle("Drafting note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save note") {
                        saving = true
                        Task { if await model.addNote(text.trimmingCharacters(in: .whitespacesAndNewlines), quote: quote) { model.noteQuote = nil; done() }; saving = false }
                    }
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct NotesSheet: View {
    let model: CreationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    @State private var deleting: DraftingNote?

    private func row(_ n: DraftingNote) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(n.anchorQuote == nil ? "On the chapter" : (model.isPlaced(n) ? "On a passage" : "can’t place · the passage has changed"))
                .font(.caption).foregroundStyle(n.anchorQuote != nil && !model.isPlaced(n) ? Color.orange : connection.theme.muted)
            if let q = n.anchorQuote, !q.isEmpty { Text("“\(q.prefix(160))”").font(.footnote).italic().foregroundStyle(connection.theme.muted) }
            Text(n.noteText).font(.callout)
            HStack(spacing: 10) {
                Button { Task { await model.setNote(n, open: !n.isOpen) } } label: { Label(n.isOpen ? "Clear" : "Reopen", systemImage: n.isOpen ? "checkmark" : "arrow.uturn.backward") }
                Button(role: .destructive) { deleting = n } label: { Label("Delete", systemImage: "trash") }
            }
            .font(.footnote).buttonStyle(.glass)
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Open") {
                    ForEach(model.openNotes) { row($0) }
                    if model.openNotes.isEmpty { Text("None").foregroundStyle(connection.theme.muted) }
                }
                let cleared = model.notes.filter { !$0.isOpen }
                if !cleared.isEmpty { Section("Cleared") { ForEach(cleared) { row($0) } } }
            }
            .navigationTitle("Drafting notes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { if let n = deleting { Task { await model.deleteNote(n) } }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Puts the on-screen keyboard away (the text keeps what it has; tapping it brings the keyboard back).
@MainActor func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct RefsTarget: Identifiable {
    let beatId: Int
    /// A name with no codex entry that is being linked to one, or nil to add a reference.
    var linking: String?
    var id: String { "\(beatId)-\(linking ?? "")" }
}
