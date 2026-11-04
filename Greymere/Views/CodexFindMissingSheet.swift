import SwiftUI

/// Find missing: pick a book, scan its synopsis for characters, places, objects and lore it names that the Codex does
/// not have, then develop each into a new entry, link it to an existing entry, or dismiss it.
struct CodexFindMissingSheet: View {
    @Bindable var model: CodexModel
    let client: APIClient
    var open: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    @State private var bookId: Int?
    @State private var list: CodexGapList?
    @State private var hasSynopsis = true
    @State private var loading = false
    @State private var scanning = false
    @State private var message: String?
    @State private var confirmScan = false
    @State private var confirmClear = false
    @State private var developing: CodexGap?
    @State private var linking: CodexGap?
    @State private var showDismissed = false
    private static let bookKey = "greymere.codexGapBook"

    private var theme: ThemeStore { connection.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    bookPicker
                    if let message { Text(message).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(12).glassEffect(.regular, in: .rect(cornerRadius: 14)) }
                    if scanning { HStack { ProgressView(); Text("Reading the synopsis… this can take a minute.").foregroundStyle(theme.muted) } }
                    else if bookId != nil { content }
                }
                .padding()
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Find missing").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await model.loadBooks(); if bookId == nil { let saved = UserDefaults.standard.integer(forKey: Self.bookKey); if saved != 0, model.books.contains(where: { $0.id == saved }) { bookId = saved; await refresh() } } }
        .confirmationDialog("Scan this book's synopsis?", isPresented: $confirmScan, titleVisibility: .visible) {
            Button("Scan") { Task { await scan() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("One model call reads the locked synopsis and lists what the Codex is missing. Items you have already dealt with are kept.") }
        .confirmationDialog("Clear the untouched items?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Task { await act { await model.clearGaps(book: bookId ?? 0) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Items you have not touched are removed, so the next scan rebuilds the list clean. Created and dismissed items stay.") }
        .sheet(item: $developing) { gap in
            CodexEditSheet(model: model, client: client, id: nil, onCreated: { _ in Task { await refresh() } },
                           prefill: (gap.name, gap.codexType, gap.id))
        }
        .sheet(item: $linking) { gap in CodexLinkPicker(model: model, gap: gap) { entry in Task { await act { await model.linkGap(gap.id, to: entry) } } } }
    }

    // MARK: book

    private var bookPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Book").font(.footnote).foregroundStyle(theme.muted)
            Menu {
                ForEach(model.books) { b in Button(b.number.map { "\($0). \(b.title)" } ?? b.title) { bookId = b.id; UserDefaults.standard.set(b.id, forKey: Self.bookKey); Task { await refresh() } } }
            } label: {
                HStack {
                    Text(model.books.first { $0.id == bookId }?.title ?? "Choose a book").foregroundStyle(bookId == nil ? theme.muted : theme.text)
                    Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: the list

    @ViewBuilder private var content: some View {
        if !hasSynopsis {
            Text("This book has no locked synopsis yet, so there is nothing to scan.").foregroundStyle(theme.muted)
        } else if let list {
            HStack(spacing: 10) {
                pill("Open", list.counts.open); pill("Created", list.counts.created); pill("Dismissed", list.counts.dismissed)
            }
            Button { confirmScan = true } label: { tile(list.items.isEmpty ? "Scan the synopsis" : "Scan again", "doc.text.magnifyingglass") }.buttonStyle(.plain)
            let open = list.items.filter { $0.state == "open" }
            if !open.isEmpty { section("Open: to create", open) { gap in openRow(gap) } }
            let created = list.items.filter { $0.state == "created" }
            if !created.isEmpty { section("Created", created) { gap in entryRow(gap, symbol: "checkmark.circle.fill") } }
            let existing = list.items.filter { $0.state == "existing" }
            if !existing.isEmpty { section("Already in the Codex", existing) { gap in entryRow(gap, symbol: "book.closed") } }
            let dismissed = list.items.filter { $0.state == "dismissed" }
            if !dismissed.isEmpty {
                Button { showDismissed.toggle() } label: { Label("Dismissed (\(dismissed.count))", systemImage: showDismissed ? "chevron.down" : "chevron.right").font(.footnote).foregroundStyle(theme.muted) }.buttonStyle(.plain)
                if showDismissed { ForEach(dismissed) { gap in dismissedRow(gap) } }
            }
            if !list.items.isEmpty { Button("Clear the untouched items") { confirmClear = true }.font(.footnote).foregroundStyle(theme.muted) }
        } else if loading { ProgressView() }
    }

    private func section(_ title: String, _ items: [CodexGap], @ViewBuilder row: @escaping (CodexGap) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(theme.muted)
            ForEach(items) { row($0) }
        }
    }

    private func openRow(_ gap: CodexGap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: gap.codexType.symbol).foregroundStyle(theme.muted)
                Text(gap.name).font(.body.weight(.semibold)).foregroundStyle(theme.text)
                Spacer(); Text(gap.codexType.single).font(.caption).foregroundStyle(theme.faint)
            }
            HStack(spacing: 8) {
                small("Develop", "plus") { developing = gap }
                small("Link", "link") { linking = gap }
                small("Dismiss", "xmark") { Task { await act { await model.dismissGap(gap.id) } } }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func entryRow(_ gap: CodexGap, symbol: String) -> some View {
        Button { if let e = gap.entry { open(e.id) } } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.name).foregroundStyle(theme.text)
                    if let n = gap.entry?.name, n != gap.name { Text("is \(n)").font(.caption).foregroundStyle(theme.muted) }
                }
                Spacer(); Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func dismissedRow(_ gap: CodexGap) -> some View {
        HStack {
            Text(gap.name).foregroundStyle(theme.muted); Spacer()
            small("Put back", "arrow.uturn.backward") { Task { await act { await model.reopenGap(gap.id) } } }
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func pill(_ title: String, _ n: Int) -> some View {
        VStack(spacing: 2) { Text("\(n)").font(.title3.weight(.semibold)).foregroundStyle(theme.text); Text(title).font(.caption).foregroundStyle(theme.muted) }
            .frame(maxWidth: .infinity).padding(.vertical, 10).glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func small(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.footnote.weight(.medium)).foregroundStyle(theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7).glassEffect(.regular.interactive(), in: .capsule)
        }.buttonStyle(.plain)
    }

    private func tile(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.body.weight(.medium)).foregroundStyle(theme.text)
            .frame(maxWidth: .infinity).padding(.vertical, 12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    // MARK: actions

    private func refresh() async {
        guard let bookId else { return }
        loading = true; defer { loading = false }
        switch await model.worklist(book: bookId) {
        case .success(let w): hasSynopsis = w.hasSynopsis; list = w.findMissing; message = nil
        case .failure(let f): message = f.text; list = nil
        }
    }

    private func scan() async {
        guard let bookId else { return }
        scanning = true; message = nil
        if let err = await model.scan(book: bookId, force: (list?.items.isEmpty == false)) { message = err }
        scanning = false
        await refresh()
    }

    private func act(_ work: () async -> String?) async {
        if let err = await work() { message = err }
        await refresh()
    }
}

/// Picks the existing entry a gap really is.
private struct CodexLinkPicker: View {
    @Bindable var model: CodexModel
    let gap: CodexGap
    var pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let hits = model.list(type: gap.codexType, query: query)
                ForEach(hits) { h in
                    Button { pick(h.entry.id); dismiss() } label: { Text(h.entry.name).foregroundStyle(connection.theme.text) }
                }
            }
            .searchable(text: $query, prompt: "Find the \(gap.codexType.single.lowercased())")
            .navigationTitle("Link “\(gap.name)”").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
