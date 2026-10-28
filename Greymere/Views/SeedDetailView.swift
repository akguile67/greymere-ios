import SwiftUI

/// The seed screen, read-only: what the desktop's seed screen shows without its conversation or controls.
/// The title and cover come from the shelf so the screen opens at once; the rest is read from the server.
struct SeedDetailView: View {
    let item: ShelfItem
    let client: APIClient
    var showsBar = false
    var isExpanded = false
    var onToggleExpand: (() -> Void)?
    let onClose: (() -> Void)?
    @Environment(ConnectionModel.self) private var connection
    @State private var model = SeedModel()
    @State private var open: Set<String> = ["Synopsis"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if onClose != nil || onToggleExpand != nil { controls }
                hero
                if let idea = model.idea {
                    if let synopsis = clean(idea.synopsis) { collapsible("Synopsis") { Blocks(text: synopsis) } }
                    if let brief = clean(idea.developedBrief) { collapsible("Card brief") { Blocks(text: brief) } }
                    if !model.papers.isEmpty { researchCard }
                } else if model.failed {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This seed couldn't be loaded.").foregroundStyle(connection.theme.muted)
                        Button("Try again") { Task { await model.load(id: item.rawId, using: client) } }
                            .buttonStyle(.glass)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .background(connection.theme.background.ignoresSafeArea())
        .environmentBar(showsBar)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.rawId) { await model.load(id: item.rawId, using: client) }
        .refreshable { await model.load(id: item.rawId, using: client) }
    }

    private func clean(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Spacer()
            if let onToggleExpand {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold)).padding(6)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel(isExpanded ? "Show Home beside the seed" : "Use the whole screen for the seed")
            }
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").font(.body.weight(.semibold)).padding(6) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("Close")
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverView(url: client.asset(item.coverUrl), seed: true).frame(width: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("Seed").font(.caption).foregroundStyle(connection.theme.muted)
                Text(item.title).font(.serif(26))
                if let line = lastActive { Text(line).font(.footnote).foregroundStyle(connection.theme.muted) }
            }
        }
    }

    private var lastActive: String? {
        guard let ts = model.idea?.lastActiveAt ?? item.activityAt else { return nil }
        let when = Fmt.when(ts)
        return "Last active \(Fmt.date(ts))" + (when.isEmpty ? "" : " · \(when.lowercased())")
    }

    /// A card that shows only its title until tapped, as in Book Details. A seed's synopsis starts open (it is short);
    /// the card brief runs to several thousand characters, so it starts closed.
    private func collapsible<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(title)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { if isOpen { open.remove(title) } else { open.insert(title) } }
            } label: {
                HStack {
                    Text(title).font(.serif(19, relativeTo: .headline))
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0)).foregroundStyle(connection.theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            if isOpen { content() }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var researchCard: some View {
        collapsible("Research") {
            ForEach(model.papers) { p in
                Text(p.title).font(.subheadline).foregroundStyle(connection.theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The few Markdown shapes a seed's text uses: headings, bullets and paragraphs (bold and italics inside them).
private struct Blocks: View {
    let text: String
    @Environment(ConnectionModel.self) private var connection

    private enum Block: Hashable { case heading(String), bullet(String), paragraph(String) }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush() }
            else if line.hasPrefix("#") {
                flush()
                out.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush(); out.append(.bullet(String(line.dropFirst(2))))
            } else { para.append(line) }
        }
        flush()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let s):
                    Text(s).font(.serif(16, relativeTo: .subheadline)).padding(.top, 4)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(connection.theme.muted)
                        Text(.init(s)).font(.callout).foregroundStyle(connection.theme.text)
                    }
                case .paragraph(let s):
                    Text(.init(s)).font(.callout).foregroundStyle(connection.theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
