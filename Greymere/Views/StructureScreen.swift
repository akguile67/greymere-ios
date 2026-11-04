import SwiftUI

/// The Structure panel (ADR 0.60.0): the book's acts with their chapter cards, as Creation lays them out; touching a card
/// brings up its briefing in place of the board, with a way back. Godric docks beside it on an iPad and rises as a sheet on
/// a phone.
struct StructureScreen: View {
    @Bindable var model: StructureModel
    let home: HomeModel
    let client: APIClient
    var onDraft: (Int) -> Void
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("greymere.activeBookId") private var activeBookId = 0
    @AppStorage("greymere.godricWidth") private var godricWidth = 400.0
    @State private var chatOpen = false
    @State private var confirmingDelete = false

    private var docked: Bool { sizeClass == .regular }
    private var chatBook: ChatBook? { model.doc.map { ChatBook(id: $0.book.id, title: $0.book.title) } }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Group {
                    if let c = model.chapter {
                        StructureCard(model: model, chapter: c)
                    } else {
                        StructureBoard(model: model, home: home, client: client, activeBookId: $activeBookId)
                    }
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
        .animation(.snappy, value: model.openAct)
        .background(connection.theme.background.ignoresSafeArea())
        .topBand(true, title: "Structure")
        .glassBar(isOpen: chatOpen, inline: barActions) { if model.doc != nil { chatOpen.toggle() } }
        .overlay(alignment: .top) {
            if let b = model.banner {
                Text(b.text).font(.footnote).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(connection.theme.surface, in: Capsule()).overlay(Capsule().strokeBorder(connection.theme.faint.opacity(0.5)))
                    .padding(.top, 56).padding(.horizontal, 16).transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.banner = nil }
            }
        }
        .animation(.snappy, value: model.banner?.id)
        .sheet(isPresented: Binding(get: { chatOpen && !docked }, set: { chatOpen = $0 })) {
            if let chatBook {
                GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .sheet(item: $model.sheet) { s in
            switch s {
            case .add(let a): StructureAddSheet(model: model, actId: a)
            case .rename(let c): StructureRenameSheet(model: model, chapterId: c)
            case .delete(let c): StructureDeleteSheet(model: model, chapterId: c)
            }
        }
        .sheet(item: $model.conflict) { c in StructureConflictSheet(model: model, conflict: c) }
        .task { await model.load(books: home.inPlan, preferred: activeBookId, client: client) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reload() } } }
    }

    /// The open card's actions, set in the glass bar: Commit while it is being briefed, Draft once it is briefed, and the
    /// chapter menu (Rename, Delete, and Unlock) beside them.
    private var barActions: AnyView? {
        guard let c = model.chapter else { return nil }
        return AnyView(HStack(spacing: 12) {
            if c.isBriefed {
                GlassPill(title: "Draft", systemImage: "square.and.pencil", prominent: true, label: "Draft this chapter in Creation") { onDraft(c.id) }
            } else {
                GlassPill(title: "Commit", systemImage: "checkmark", prominent: true, label: "Commit the briefing") {
                    dismissKeyboard()
                    Task { await model.commit(c.id) }
                }.disabled(model.busy)
            }
            StructureChapterMenu(model: model, chapter: c)
        })
    }
}

struct StructureChapterMenu: View {
    let model: StructureModel
    let chapter: StructureChapter
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        let size: CGFloat = sizeClass == .regular ? 60 : 44
        Menu {
            Button("Rename", systemImage: "pencil") { model.sheet = .rename(chapter.id) }
            if chapter.isBriefed { Button("Unlock briefing to edit", systemImage: "lock.open") { Task { await model.unlock(chapter.id) } } }
            Button("Delete…", systemImage: "trash", role: .destructive) { model.sheet = .delete(chapter.id) }
        } label: {
            Image(systemName: "ellipsis").font((sizeClass == .regular ? Font.title3 : .body).weight(.semibold))
                .foregroundStyle(connection.theme.text).frame(width: size, height: size).contentShape(Circle())
        }
        .glassEffect(.regular.tint(connection.theme.glassTint).interactive(), in: .circle)
        .accessibilityLabel("Chapter actions")
    }
}

// MARK: board

private struct StructureBoard: View {
    @Bindable var model: StructureModel
    let home: HomeModel
    let client: APIClient
    @Binding var activeBookId: Int
    @Environment(ConnectionModel.self) private var connection
    @Environment(ShellModel.self) private var shell

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let error = model.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(connection.theme.muted)
                        Button("Try again") { Task { await model.reload() } }.buttonStyle(.glass)
                    }
                } else if let doc = model.doc {
                    if !doc.lockedSynopsis {
                        VStack(spacing: 10) {
                            Text("No locked synopsis yet").font(.headline)
                            Text("Structure builds its acts from the book synopsis. Lock it in Ideation first.")
                                .font(.footnote).foregroundStyle(connection.theme.muted).multilineTextAlignment(.center)
                            Button("Open Ideation") { shell.open(.ideation) }.buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    } else {
                        ForEach(doc.acts) { StructureActCard(model: model, act: $0) }
                    }
                } else if model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if home.inPlan.isEmpty {
                    Text("No books are in the plan.").foregroundStyle(connection.theme.muted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 110)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await model.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(home.inPlan) { b in
                    Button {
                        activeBookId = b.rawId
                        Task { await model.select(book: b.rawId) }
                    } label: { if b.rawId == model.bookId { Label(b.title, systemImage: "checkmark") } else { Text(b.title) } }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.doc?.book.title ?? home.inPlan.first { $0.rawId == model.bookId }?.title ?? "Choose a book").font(.serif(24))
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.foregroundStyle(connection.theme.text)
            }
            if let doc = model.doc, doc.lockedSynopsis {
                let done = model.draftedActs
                Text(done == doc.acts.count && done > 0 ? "All \(done) acts drafted, the book has moved to Editing" : "\(done) / \(doc.acts.count) acts drafted")
                    .font(.footnote).foregroundStyle(connection.theme.muted)
            }
        }
    }
}

private struct StructureActCard: View {
    @Bindable var model: StructureModel
    let act: StructureAct
    @Environment(ConnectionModel.self) private var connection
    private var synopsisOpen: Bool { model.openActSynopsis.contains(act.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(act.title == act.label || act.title.isEmpty ? act.label : "\(act.label) · \(act.title)").font(.headline).foregroundStyle(connection.theme.text)
                Pill(text: act.badge, tint: act.badge == "Drafted" ? .green : act.badge == "In progress" ? connection.theme.accent : connection.theme.muted)
                Spacer(minLength: 8)
                Text("\(act.draftedCount)/\(act.chapterCount) drafted · \(act.briefedCount) briefed\(act.wordTarget.map { " · \(Int($0 / 1000))k words" } ?? "")")
                    .font(.caption).foregroundStyle(connection.theme.faint).lineLimit(1)
            }
            if let o = act.outstandingLine { Text("Outstanding: **\(o.0)** — \(o.1)").font(.caption).foregroundStyle(connection.theme.muted) }
            synopsis
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(act.chapters) { StructureChapterRow(model: model, chapter: $0) }
                Button { model.sheet = .add(act.id) } label: {
                    Label("Add chapter to \(act.label)", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: 84)
                        .foregroundStyle(connection.theme.muted)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }.buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .dropDestination(for: String.self) { items, _ in
            if let id = items.first.flatMap({ Int($0) }) { model.refuseDrop(id, onAct: act.id) }
            return true
        }
    }

    /// The act's synopsis: closed until asked for, read-only, with its lock state. It is changed in Ideation.
    private var synopsis: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { model.toggleSynopsis(act.id) } } label: {
                HStack {
                    Text("Synopsis").font(.subheadline)
                    Pill(text: act.synopsisLocked ? "locked & synced" : "not locked", tint: act.synopsisLocked ? .green : .orange)
                    Spacer()
                    Text(synopsisOpen ? "Hide" : "Show").font(.caption)
                    Image(systemName: synopsisOpen ? "chevron.up" : "chevron.right").font(.caption2)
                }.foregroundStyle(connection.theme.text)
            }.buttonStyle(.plain)
            if synopsisOpen {
                Text(act.synopsis?.isEmpty == false ? act.synopsis! : "No synopsis text for this act.")
                    .font(.footnote).foregroundStyle(connection.theme.muted).textSelection(.enabled)
            }
        }
        .padding(10).background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var tint: Color
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule()).foregroundStyle(tint).lineLimit(1)
    }
}

/// A chapter as a card in the act's grid, in Creation's manner. Touch opens its briefing; hold and drag moves it within the act.
private struct StructureChapterRow: View {
    let model: StructureModel
    let chapter: StructureChapter
    @Environment(ConnectionModel.self) private var connection
    @State private var targeted = false

    var body: some View {
        let stage = model.creationStatus[chapter.id]
        Button { Task { await model.open(chapter.id) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.badges[chapter.id] ?? "Ch \(chapter.number)").font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
                    Spacer(minLength: 6)
                    if chapter.codexWarning?.isEmpty == false {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Codex gap: \(chapter.codexWarning!.map(\.name).joined(separator: ", "))")
                    }
                    StructureStateChip(chapter: chapter, creation: stage)
                }
                Text(chapter.title).font(.body.weight(.medium)).foregroundStyle(connection.theme.text)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Text(chapter.summary?.isEmpty == false ? chapter.summary! : "Brief this chapter").font(.caption).foregroundStyle(connection.theme.muted).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(targeted ? connection.theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .draggable(String(chapter.id))
        .dropDestination(for: String.self, action: { items, _ in
            if let id = items.first.flatMap({ Int($0) }) { Task { await model.move(id, onto: chapter.id) } }
            return true
        }, isTargeted: { targeted = $0 })
    }
}

/// Where a chapter stands: Drafted or Drafting once Creation has it, otherwise its briefing state.
struct StructureStateChip: View {
    let chapter: StructureChapter
    let creation: String?
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        if creation == "draft_one" { Pill(text: "Drafted", tint: .green) }
        else if creation == "drafting" { Pill(text: "Drafting", tint: .orange) }
        else { Pill(text: chapter.stateLabel, tint: chapter.isBriefed ? connection.theme.accent : chapter.isActive ? .blue : connection.theme.muted) }
    }
}

// MARK: card

/// A chapter card: the summary headline on top, the other five briefing fields as sections that open and close.
private struct StructureCard: View {
    @Bindable var model: StructureModel
    let chapter: StructureChapter
    @Environment(ConnectionModel.self) private var connection
    @State private var expanded: Set<BriefField> = []
    @FocusState private var focus: BriefField?

    var body: some View {
        let ro = chapter.isBriefed
        VStack(spacing: 0) {
            HStack {
                Button { Task { await model.save(chapter.id) }; model.chapterId = nil } label: { Label(model.act(of: chapter.id)?.label ?? "Board", systemImage: "chevron.left") }
                Spacer()
            }.padding(.horizontal, 16).padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.staged.contains(chapter.id) && !ro {
                        Text("Godric staged this brief. It is not committed yet: edit the fields if you like, then Commit.")
                            .font(.footnote).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(connection.theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    HStack(spacing: 6) {
                        Text("Chapter \(chapter.number)").font(.caption).foregroundStyle(connection.theme.muted)
                        StructureStateChip(chapter: chapter, creation: model.creationStatus[chapter.id])
                        Spacer()
                    }
                    Text(chapter.title).font(.serif(26))
                    if let gaps = chapter.codexWarning, !gaps.isEmpty {
                        Label("Codex gaps: " + gaps.map(\.name).joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    summary(ro)
                    ForEach(BriefField.allCases.filter { $0 != .summary }) { section($0, ro) }
                    if ro {
                        Button("Unlock briefing to edit") { Task { await model.unlock(chapter.id) } }.buttonStyle(.bordered)
                    } else {
                        Text("Saved as you leave each field. Not committed until you press Commit.").font(.caption).foregroundStyle(connection.theme.muted)
                    }
                }
                .padding(16).padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: focus) { old, _ in if old != nil { Task { await model.save(chapter.id) } } }
        .onDisappear { Task { await model.save(chapter.id) } }
        .onChange(of: chapter.id) { _, _ in expanded = [] }
    }

    private func summary(_ ro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUMMARY HEADLINE").font(.caption2.weight(.semibold)).foregroundStyle(connection.theme.muted)
            if ro { Text(chapter.summary?.isEmpty == false ? chapter.summary! : "No summary yet.") }
            else {
                TextField("One line on what this chapter is", text: binding(.summary), axis: .vertical).lineLimit(1...5).focused($focus, equals: .summary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func section(_ f: BriefField, _ ro: Bool) -> some View {
        let value = model.text(chapter, f)
        let open = expanded.contains(f)
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { if open { expanded.remove(f) } else { expanded.insert(f) } } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(f.title).font(.subheadline.weight(.semibold)).foregroundStyle(connection.theme.text)
                    if !open, !value.isEmpty { Text(value).font(.caption).foregroundStyle(connection.theme.muted).lineLimit(1) }
                    Spacer(minLength: 4)
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                if ro { Text(value.isEmpty ? "—" : value).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).textSelection(.enabled) }
                else {
                    TextField(f.title, text: binding(f), axis: .vertical).lineLimit(2...10).focused($focus, equals: f)
                        .padding(8).background(connection.theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(.top, 8)
                }
            }
        }
        .padding(10).background(connection.theme.surface.opacity(ro ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func binding(_ f: BriefField) -> Binding<String> {
        Binding(get: { model.text(chapter, f) }, set: { model.setText(chapter, f, $0) })
    }
}

// MARK: sheets

private struct StructureAddSheet: View {
    let model: StructureModel
    let actId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Adds to the end of \(model.doc?.acts.first { $0.id == actId }?.label ?? "the act")") { TextField("Title", text: $title) }
                Section { Text("Chapters after it move up by one and their “Chapter N” labels follow. Every detail is editable afterwards.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Add chapter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { let t = title; dismiss(); Task { await model.addChapter(to: actId, title: t) } } }
            }
        }.presentationDetents([.medium])
    }
}

private struct StructureRenameSheet: View {
    let model: StructureModel
    let chapterId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $title); Text("Blank becomes “Untitled chapter”.").font(.footnote).foregroundStyle(.secondary) }
                .navigationTitle("Rename chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { let t = title; dismiss(); Task { await model.rename(chapterId, to: t) } } }
                }
        }.presentationDetents([.medium]).onAppear { title = model.chapter(chapterId)?.title ?? "" }
    }
}

private struct StructureDeleteSheet: View {
    let model: StructureModel
    let chapterId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    var body: some View {
        let title = model.chapter(chapterId)?.title ?? ""
        NavigationStack {
            Form {
                Section { Text(model.footprint?.sentence ?? "Checking what this takes with it…").font(.callout).foregroundStyle(.red) }
                Section("Type the title to confirm: \(title)") { TextField("Title", text: $typed).autocorrectionDisabled() }
                Section { Button("Delete chapter", role: .destructive) { dismiss(); Task { await model.delete(chapterId) } }.disabled(typed != title || model.footprint == nil) }
            }
            .navigationTitle("Delete chapter").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await model.loadFootprint(chapterId) }
    }
}

/// The chapter changed on the other device while this one was editing: one choice for the whole card, with the fields that
/// differ listed. The two choices stay in view at the foot.
private struct StructureConflictSheet: View {
    let model: StructureModel
    let conflict: StructureConflict
    var body: some View {
        NavigationStack {
            List {
                Section { Text("This chapter was changed on another device. Your \(conflict.thenCommit ? "Commit" : "save") was not applied. These fields differ:").font(.callout) }
                ForEach(conflict.diffs) { d in
                    Section(d.field.title) {
                        VStack(alignment: .leading, spacing: 2) { Text("This device").font(.caption).foregroundStyle(.secondary); Text(d.mine.isEmpty ? "(empty)" : d.mine) }
                        VStack(alignment: .leading, spacing: 2) { Text("The other device").font(.caption).foregroundStyle(.secondary); Text(d.theirs.isEmpty ? "(empty)" : d.theirs) }
                    }
                }
            }
            .navigationTitle("Changed elsewhere").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text("One choice for the whole card.").font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Use the other device") { Task { await model.resolve(conflict, useThisDevice: false) } }.buttonStyle(.bordered)
                        Button("Use this device") { Task { await model.resolve(conflict, useThisDevice: true) } }.buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                }.padding().frame(maxWidth: .infinity).background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
