import SwiftUI

/// The Ideation panel: the book's synopsis, a book chip to change book, and Godric on call. On iPhone Godric rises as
/// a sheet over the synopsis; on iPad he docks beside it. Everything the author does is a call to a server that
/// already does it (ADR 0.54.0).
struct IdeationScreen: View {
    @Bindable var model: IdeationModel
    let home: HomeModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("greymere.activeBookId") private var activeBookId = 0
    @State private var chatOpen = false

    private var books: [ShelfItem] { home.inPlan }
    private var current: ShelfItem? { books.first { $0.rawId == activeBookId } ?? books.first }
    private var docked: Bool { sizeClass == .regular }
    private var chatBook: ChatBook? { current.map { ChatBook(id: $0.rawId, title: $0.title) } }

    var body: some View {
        HStack(spacing: 0) {
            synopsisPane
            if docked && chatOpen, let chatBook {
                Divider()
                GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                    .frame(width: 400)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: chatOpen)
        .onChange(of: chatOpen) { _, open in if !open { model.godric.leaveHistory() } }
        .background(connection.theme.background.ignoresSafeArea())
        .topBand(true, title: "Ideation")
        .glassBar(isOpen: chatOpen) { chatOpen.toggle() }
        .sheet(isPresented: Binding(get: { chatOpen && !docked }, set: { chatOpen = $0 })) {
            if let chatBook {
                GodricChatView(model: model.godric, client: client, showsBar: false, book: chatBook, onClose: { chatOpen = false })
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .task(id: current?.rawId) {
            guard let current else { return }
            activeBookId = current.rawId
            model.onLocked = { await home.load(using: client) }
            await model.load(bookId: current.rawId, title: current.title, client: client)
        }
        .onChange(of: model.godric.synopsisTick) { Task { await model.synopsisChangedByGodric() } }
        .alert("Lock this synopsis?", isPresented: $model.confirmLock) {
            Button("Cancel", role: .cancel) {}
            Button("Lock synopsis") { Task { await model.lock() } }
        } message: {
            Text("It is saved to the codex as the synopsis Godric reads, ideation is marked complete and the book moves on to the Codex update.")
        }
        .alert("The synopsis changed", isPresented: Binding(get: { model.theirs != nil }, set: { if !$0 { model.theirs = nil } })) {
            Button("Keep mine") { Task { await model.keepMine() } }
            Button("Take theirs") { model.takeTheirs() }
            Button("Copy mine, take theirs") { model.takeTheirs(copyMine: true) }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("It was edited since you started (on the laptop, or by Godric). Nothing has been overwritten.")
        }
    }

    // MARK: synopsis

    private var synopsisPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let banner = model.banner { bannerView(banner) }
                    if let proposal = model.proposal { proposalCard(proposal) }
                    if books.isEmpty {
                        Text(home.summary == nil ? "Loading…" : "No books in work.").foregroundStyle(connection.theme.muted)
                    } else if let error = model.loadError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).foregroundStyle(connection.theme.muted)
                            Button("Try again") { Task { if let c = current { await model.load(bookId: c.rawId, title: c.title, client: client) } } }
                                .buttonStyle(.glass)
                        }
                    } else {
                        synopsisBody
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            actions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(books) { book in
                    Button { activeBookId = book.rawId } label: {
                        if book.rawId == current?.rawId { Label(book.title, systemImage: "checkmark") } else { Text(book.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current?.title ?? "Choose a book").font(.serif(24))
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(connection.theme.text)
            }
            .disabled(books.isEmpty || model.editing)
            .accessibilityLabel("Book: \(current?.title ?? "none"). Change book")
            if let methodology = model.methodology {
                Text("Methodology: \(methodology)").font(.caption).foregroundStyle(connection.theme.muted)
            }
            Text(model.turns == 0 ? "New conversation — start the debate." : "\(model.turns) turns" + (model.lastActive.map { " · last active \($0)" } ?? ""))
                .font(.caption).foregroundStyle(connection.theme.faint)
        }
    }

    private func bannerView(_ banner: IdeationModel.Banner) -> some View {
        HStack(alignment: .top) {
            Text(banner.text).font(.footnote).foregroundStyle(banner.isError ? Color.red : connection.theme.text)
            Spacer(minLength: 8)
            Button { model.banner = nil } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(banner.isError ? Color.red : connection.theme.faint.opacity(0.5)))
    }

    /// What Godric (or Refresh) has drafted. The synopsis itself is untouched until the author presses Apply.
    private func proposalCard(_ p: SynopsisProposal) -> some View {
        let stale = p.stale == true
        return VStack(alignment: .leading, spacing: 10) {
            Label(stale ? "A drafted change is out of date" : "Drafted change: not applied yet", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
            Text(stale ? "The synopsis has changed since this was drafted. Discard it and ask Godric to draft it again."
                       : "Read it through. The synopsis stays as it is until you press Apply, here or in the bar at the bottom.")
                .font(.footnote).foregroundStyle(connection.theme.muted)
            ForEach(p.changes) { change in
                VStack(alignment: .leading, spacing: 6) {
                    if change.before.isEmpty {
                        Text("NEW PARAGRAPH").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    } else if change.after.isEmpty {
                        Text("REMOVED").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                    } else {
                        Text("CHANGED").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                    if !change.before.isEmpty, !change.after.isEmpty {
                        Text(DiffText.marked(before: change.before, after: change.after, theme: connection.theme))
                            .font(.footnote).foregroundStyle(connection.theme.text)
                    } else if !change.before.isEmpty {
                        Text(change.before).font(.footnote).strikethrough(true, color: .red.opacity(0.6))
                            .foregroundStyle(connection.theme.muted)
                    } else {
                        Text(change.after).font(.footnote).foregroundStyle(connection.theme.text)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(connection.theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 10) {
                Button { Task { await model.applyProposal() } } label: { Label("Apply", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).disabled(stale || model.working != nil)
                Button("Discard") { Task { await model.discardProposal() } }
                    .buttonStyle(.glass).disabled(model.working != nil)
            }
        }
        .padding(12)
        .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.6)))
    }

    private var synopsisBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(model.hasSaved ? "Saved synopsis" : "Developing synopsis", systemImage: "doc.text")
                    .font(.caption.weight(.semibold)).foregroundStyle(connection.theme.muted).lineLimit(1)
                if model.hasSynopsis {
                    Text("\(model.wordCount) words").font(.caption).foregroundStyle(connection.theme.faint).lineLimit(1)
                }
                if model.working == .refreshing { ProgressView().controlSize(.mini); Text("Refreshing…").font(.caption).foregroundStyle(connection.theme.muted) }
            }
            if model.changedByGodric && !model.editing {
                Label("Updated by Godric", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            if model.editing {
                TextEditor(text: $model.editText)
                    .font(.body).frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(connection.theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if model.hasSynopsis {
                Blocks(text: model.synopsis).textSelection(.enabled)
            } else if model.loading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The synopsis builds here as you and Godric reach decisions.")
                    Text("When you are ready, ask Godric to propose a draft. He drafts it here for you to read, and nothing is written until you press Apply.")
                    Text("When the synopsis is usable, tap Lock synopsis. It becomes the synopsis Godric reads everywhere, and the book moves on to the Codex update.")
                }
                .font(.subheadline).foregroundStyle(connection.theme.muted)
            }
        }
    }

    // MARK: actions

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if model.editing {
                Button { Task { await model.saveEdit() } } label: { Label("Done editing", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).disabled(model.working != nil)
                Button("Cancel") { model.cancelEdit() }.buttonStyle(.glass)
            } else if let proposal = model.proposal {
                // A drafted change is waiting: the only choices are to apply it or throw it away.
                Button { Task { await model.applyProposal() } } label: { Label("Apply drafted change", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).disabled(proposal.stale == true || model.working != nil)
                Button("Discard") { Task { await model.discardProposal() } }
                    .buttonStyle(.glass).disabled(model.working != nil)
            } else {
                Button { Task { await model.requestLock() } } label: { Label("Lock synopsis", systemImage: "lock") }
                    .buttonStyle(.glassProminent).disabled(!model.hasSynopsis || model.working != nil)
                Button { model.beginEdit() } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.glass).disabled(!model.hasSynopsis || model.working != nil)
            }
        }
        .labelStyle(.titleAndIcon).font(.subheadline).lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
    }
}
