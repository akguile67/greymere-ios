import SwiftUI

/// The Structure panel (ADR 0.60.0): the book's acts, the chapter cards inside them, the six-field briefing on a card,
/// and Godric. iPad landscape is a split (board left, card right) with Godric docked as a third column; everywhere else
/// the board and the card take turns on one screen, and Godric rises as a sheet on a phone.
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
            let split = sizeClass == .regular && geo.size.width > geo.size.height
            HStack(spacing: 0) {
                Group {
                    if split {
                        HStack(spacing: 0) {
                            StructureBoard(model: model, home: home, client: client, activeBookId: $activeBookId, split: true).frame(width: 380)
                            Divider()
                            Group {
                                if let c = model.chapter { StructureCard(model: model, chapter: c, showsBack: false) }
                                else { ContentUnavailableView("Open a chapter", systemImage: "rectangle.on.rectangle", description: Text("Choose a chapter card on the left.")) }
                            }.frame(maxWidth: .infinity)
                        }
                    } else if let c = model.chapter {
                        StructureCard(model: model, chapter: c, showsBack: true)
                    } else {
                        StructureBoard(model: model, home: home, client: client, activeBookId: $activeBookId, split: false)
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
    let split: Bool
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
    private var isOpen: Bool { model.openAct == act.id }
    private var synopsisOpen: Bool { model.openActSynopsis.contains(act.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.toggleAct(act.id) } label: {
                HStack {
                    Text(act.title == act.label || act.title.isEmpty ? act.label : "\(act.label) · \(act.title)").font(.headline).foregroundStyle(connection.theme.text)
                    Spacer()
                    Pill(text: act.badge, tint: act.badge == "Drafted" ? .green : act.badge == "In progress" ? connection.theme.accent : connection.theme.muted)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(connection.theme.muted)
                }
            }.buttonStyle(.plain)
            HStack(spacing: 5) {
                Pill(text: "\(act.chapterCount) ch", tint: connection.theme.muted)
                Pill(text: act.wordTarget.map { "\(Int($0 / 1000))k" } ?? "n/a", tint: connection.theme.muted)
                Pill(text: "briefed \(act.briefedCount)/\(act.chapterCount)", tint: connection.theme.muted)
                Pill(text: "drafted \(act.draftedCount)/\(act.chapterCount)", tint: connection.theme.muted)
            }
            if let o = act.outstandingLine { Text("Outstanding: **\(o.0)** — \(o.1)").font(.caption).foregroundStyle(connection.theme.muted) }
            if isOpen {
                synopsis
                ForEach(act.chapters) { StructureChapterRow(model: model, chapter: $0) }
                Button { model.sheet = .add(act.id) } label: {
                    Label("Add chapter to \(act.label)", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(connection.theme.text)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(connection.theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isOpen ? connection.theme.accent.opacity(0.6) : connection.theme.faint.opacity(0.4)))
        .dropDestination(for: String.self) { items, _ in
            if let id = items.first.flatMap({ Int($0) }) { model.refuseDrop(id, onAct: act.id) }
            return true
        }
    }

    /// The act's synopsis: closed until asked for, read-only, with its lock state. It is changed in Ideation.
    private var synopsis: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.toggleSynopsis(act.id) } label: {
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
        .padding(10).background(connection.theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct StructureChapterRow: View {
    let model: StructureModel
    let chapter: StructureChapter
    @Environment(ConnectionModel.self) private var connection
    @State private var targeted = false

    var body: some View {
        let tint: Color = chapter.isBriefed ? .green : chapter.isActive ? connection.theme.accent : connection.theme.muted
        Button { Task { await model.open(chapter.id) } } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(chapter.number)").font(.caption.weight(.bold)).frame(width: 26, height: 26)
                    .background(connection.theme.faint.opacity(0.25), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(chapter.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if chapter.codexWarning?.isEmpty == false {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel("Codex entries missing")
                        }
                    }
                    Text(chapter.summary?.isEmpty == false ? chapter.summary! : "Brief this chapter").font(.caption).foregroundStyle(connection.theme.muted).lineLimit(1)
                }.foregroundStyle(connection.theme.text)
                Spacer(minLength: 4)
                Pill(text: chapter.stateLabel, tint: tint)
            }
            .padding(10).background(connection.theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? connection.theme.accent : (model.chapterId == chapter.id ? connection.theme.accent.opacity(0.6) : .clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .draggable(String(chapter.id))
        .dropDestination(for: String.self, action: { items, _ in
            if let id = items.first.flatMap({ Int($0) }) { Task { await model.move(id, onto: chapter.id) } }
            return true
        }, isTargeted: { targeted = $0 })
    }
}

// MARK: card

/// A chapter card: the summary headline on top, the other five briefing fields as sections that open and close.
private struct StructureCard: View {
    @Bindable var model: StructureModel
    let chapter: StructureChapter
    let showsBack: Bool
    @Environment(ConnectionModel.self) private var connection
    @State private var expanded: Set<BriefField> = []
    @FocusState private var focus: BriefField?

    var body: some View {
        let ro = chapter.isBriefed
        VStack(spacing: 0) {
            if showsBack {
                HStack {
                    Button { Task { await model.save(chapter.id) }; model.chapterId = nil } label: { Label(model.act(of: chapter.id)?.label ?? "Board", systemImage: "chevron.left") }
                    Spacer()
                }.padding(.horizontal, 16).padding(.vertical, 6)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.staged.contains(chapter.id) && !ro {
                        Text("Godric staged this brief. It is not committed yet: edit the fields if you like, then Commit.")
                            .font(.footnote).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(connection.theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    HStack(spacing: 6) {
                        Text("Chapter \(chapter.number)").font(.caption).foregroundStyle(connection.theme.muted)
                        Pill(text: chapter.stateLabel, tint: ro ? .green : chapter.isActive ? connection.theme.accent : connection.theme.muted)
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
        return DisclosureGroup(isExpanded: Binding(get: { expanded.contains(f) }, set: { if $0 { expanded.insert(f) } else { expanded.remove(f) } })) {
            if ro { Text(value.isEmpty ? "—" : value).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4).textSelection(.enabled) }
            else {
                TextField(f.title, text: binding(f), axis: .vertical).lineLimit(2...10).focused($focus, equals: f)
                    .padding(8).background(connection.theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(.top, 4)
            }
        } label: {
            HStack { Text(f.title).font(.subheadline.weight(.semibold)).foregroundStyle(connection.theme.text)
                if !expanded.contains(f), !value.isEmpty { Text(value).font(.caption).foregroundStyle(connection.theme.muted).lineLimit(1) } }
        }
        .tint(connection.theme.muted)
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
