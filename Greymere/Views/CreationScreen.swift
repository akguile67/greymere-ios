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
    @AppStorage("greymere.activeBookId") private var activeBookId = 0
    @State private var chatOpen = false

    private var docked: Bool { sizeClass == .regular }
    private var chatBook: ChatBook? {
        guard model.chapterId != nil, let doc = model.doc, let book = doc.book else { return nil }
        return ChatBook(id: book.id, title: book.title)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if model.chapterId == nil { CreationPicker(model: model, client: client) }
                else { CreationChapterView(model: model, client: client) }
            }
            if docked && chatOpen, let chatBook {
                Divider()
                GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                    .frame(width: 400)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: chatOpen)
        .background(connection.theme.background.ignoresSafeArea())
        .topBand(true, title: "Creation")
        .glassBar(isOpen: chatOpen) {
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
    @State private var briefOpen = true
    @State private var sheet: BeatSheetTarget?
    @State private var refsFor: RefsTarget?

    var body: some View {
        VStack(spacing: 0) {
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
                        beatsSection
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refreshOnForeground() }
            actions
        }
        .onAppear { briefOpen = sizeClass == .regular }
        .sheet(item: $sheet) { target in BeatSheet(model: model, target: target) }
        .sheet(item: $refsFor) { target in RefsSheet(model: model, beatId: target.beatId, linking: target.linking) }
    }

    private var header: some View {
        let ch = model.doc?.chapter
        let badge = model.bookDoc.flatMap { CreationModel.badges($0.acts)[model.chapterId ?? 0] }
        return VStack(alignment: .leading, spacing: 6) {
            Button { Task { await model.close() } } label: {
                Label("Chapters", systemImage: "chevron.backward").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass).disabled(model.briefEditing)
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

    private var beatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BEATS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(connection.theme.muted)
            let beats = model.doc?.beats ?? []
            if beats.isEmpty {
                Text("No beats yet. Add one below, or talk the chapter through with Godric and ask him to shape them.")
                    .font(.subheadline).foregroundStyle(connection.theme.muted)
            }
            ForEach(beats) { beat in
                BeatCard(model: model, beat: beat,
                         edit: { sheet = .edit(beat) },
                         refs: { linking in refsFor = RefsTarget(beatId: beat.id, linking: linking) },
                         fixBrief: { briefOpen = true; model.beginBriefEdit() })
            }
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
                    .buttonStyle(.glassProminent).disabled(model.working)
                Button("Discard") { Task { await model.discardProposal() } }.buttonStyle(.glass).disabled(model.working)
            }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.6)))
    }

    // MARK: bottom bar

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if let p = model.proposal, p.pending {
                Button { Task { await model.applyProposal() } } label: { Label("Apply drafted change", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).disabled(model.working)
                Button("Discard") { Task { await model.discardProposal() } }.buttonStyle(.glass).disabled(model.working)
            } else {
                Button { sheet = .add } label: { Label("Add beat", systemImage: "plus") }
                    .buttonStyle(.glassProminent).disabled(model.doc == nil || model.working || model.briefEditing)
            }
        }
        .labelStyle(.titleAndIcon).font(.subheadline).lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
    }
}

struct RefsTarget: Identifiable {
    let beatId: Int
    /// A name with no codex entry that is being linked to one, or nil to add a reference.
    var linking: String?
    var id: String { "\(beatId)-\(linking ?? "")" }
}
