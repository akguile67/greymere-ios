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
    @State private var briefOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if onClose != nil || onToggleExpand != nil { controls }
                hero
                if let idea = model.idea {
                    if let synopsis = clean(idea.synopsis) { card("Synopsis") { Blocks(text: synopsis) } }
                    if let brief = clean(idea.developedBrief) { briefCard(brief) }
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

    /// The brief runs to several thousand characters, so it opens folded and fades out, as on the desktop.
    private func briefCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Card brief").font(.serif(19, relativeTo: .headline))
            Blocks(text: text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: briefOpen ? nil : 150, alignment: .top)
                .clipped()
                .mask(alignment: .top) {
                    if briefOpen { Rectangle() }
                    else { LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom) }
                }
            Button(briefOpen ? "Show less" : "Show more") { withAnimation(.snappy) { briefOpen.toggle() } }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(connection.theme.accent)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var researchCard: some View {
        card("Research") {
            ForEach(model.papers) { p in
                Text(p.title).font(.subheadline).foregroundStyle(connection.theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.serif(19, relativeTo: .headline))
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
