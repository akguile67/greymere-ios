// THROWAWAY prototype views (ADR 0.60.0 Sprint 2): navigation only.
import SwiftUI

private func stateColor(_ s: CState) -> Color { s == .briefed ? .green : s == .active ? .blue : .secondary }

struct Chip: View {
    let text: String; var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule()).foregroundStyle(color)
    }
}

struct StructureRoot: View {
    @Environment(StructureStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sc

    var body: some View {
        @Bindable var store = store
        GeometryReader { g in
            let split = sc == .regular && g.size.width > g.size.height
            Group {
                if split {
                    HStack(spacing: 0) {
                        NavigationStack { BoardView().navigationDestination(for: String.self) { _ in EmptyView() } }.frame(width: 380)
                        Divider()
                        NavigationStack {
                            if let id = store.selected, store.chapter(id) != nil { ChapterView(id: id) }
                            else { ContentUnavailableView("Open a chapter", systemImage: "rectangle.on.rectangle", description: Text("Choose a chapter card on the left.")) }
                        }.frame(maxWidth: .infinity)
                        if store.godricOpen {
                            Divider()
                            GodricView(docked: true).frame(width: 330)
                        }
                    }
                } else {
                    NavigationStack(path: $store.path) {
                        BoardView().navigationDestination(for: String.self) { ChapterView(id: $0) }
                    }
                }
            }
            .onAppear { store.isSplit = split }
            .onChange(of: split) { _, v in store.isSplit = v; store.path = []; if !v { store.selected = nil } }
        }
        .overlay(alignment: .top) { if let b = store.banner { Text(b).font(.footnote).padding(10).background(.blue.opacity(0.15), in: Capsule()).padding(.top, 52).transition(.move(edge: .top).combined(with: .opacity)) } }
        .overlay(alignment: .bottom) { if let t = store.toast { Text(t).font(.footnote).foregroundStyle(.white).padding(12).background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 90).padding(.horizontal, 16).transition(.opacity) } }
        .animation(.snappy, value: store.toast).animation(.snappy, value: store.banner)
        .sheet(item: $store.sheet) { s in
            switch s {
            case .add(let a): AddSheet(actID: a)
            case .delete(let c): DeleteSheet(cid: c)
            case .rename(let c): RenameSheet(cid: c)
            case .stale(let c): StaleSheet(cid: c)
            }
        }
    }
}

// MARK: Board

struct BoardView: View {
    @Environment(StructureStore.self) private var store
    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.emptyBook {
                    VStack(spacing: 10) {
                        Text("No locked synopsis yet").font(.headline)
                        Text("Structure builds its acts from the book synopsis. Lock it in Ideation first.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Open Ideation") { store.say("Opens Ideation (prototype)") }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    Text("\(store.draftedActs) / \(store.acts.count) acts drafted").font(.footnote).foregroundStyle(.secondary)
                    ForEach(store.acts) { ActCard(act: $0) }
                }
            }.padding(.horizontal, 16).padding(.bottom, 24)
        }
        .navigationTitle("Structure").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(store.books, id: \.self) { b in Button { store.book = b } label: { Label(b, systemImage: b == store.book ? "checkmark" : "") } }
                } label: { HStack(spacing: 3) { Text(store.book); Image(systemName: "chevron.down").font(.caption2) }.font(.subheadline.weight(.semibold)) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Simulate: changed on another device") { store.simulateLive() }
                    Button("Simulate: next Commit is stale") { store.armStale = true; store.say("Next Commit will clash.") }
                    Button("Reset data", role: .destructive) { store.reset() }
                } label: { Image(systemName: "wrench.and.screwdriver") }
            }
        }
    }
}

struct ActCard: View {
    @Environment(StructureStore.self) private var store
    let act: PAct
    private var isOpen: Bool { store.openAct == act.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { store.toggleAct(act.id) } label: {
                HStack {
                    Text(act.title.isEmpty ? act.label : "\(act.label) · \(act.title)").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Chip(text: act.badge, color: act.badge == "Drafted" ? .green : act.badge == "In progress" ? .blue : .secondary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            HStack(spacing: 5) {
                Chip(text: "\(act.chapters.count) ch"); Chip(text: act.chapters.isEmpty ? "n/a" : "\(act.chapters.count * 2)k")
                Chip(text: "briefed \(act.briefed)/\(act.chapters.count)"); Chip(text: "drafted \(act.draftedCount)/\(act.chapters.count)")
            }
            if let o = act.outstanding { Text("Outstanding: **\(o.0)** — \(o.1)").font(.caption).foregroundStyle(.secondary) }
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.snappy) { if store.synopsisOpen.contains(act.id) { store.synopsisOpen.remove(act.id) } else { store.synopsisOpen.insert(act.id) } }
                    } label: {
                        HStack { Text("Synopsis"); Chip(text: act.locked ? "locked & synced" : "not locked", color: act.locked ? .green : .orange); Spacer()
                            Text(store.synopsisOpen.contains(act.id) ? "Hide" : "Show").font(.caption); Image(systemName: store.synopsisOpen.contains(act.id) ? "chevron.up" : "chevron.right").font(.caption2) }
                            .font(.subheadline).foregroundStyle(.primary)
                    }.buttonStyle(.plain)
                    if store.synopsisOpen.contains(act.id) { Text(act.synopsis).font(.footnote).foregroundStyle(.secondary) }
                }.padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                ForEach(act.chapters) { ChapterRow(chapter: $0) }
                Button { store.sheet = .add(act.id) } label: {
                    Label("Add chapter to \(act.label)", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.tertiary))
                }.buttonStyle(.plain)
            }
        }
        .padding(12).background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOpen ? Color.accentColor.opacity(0.6) : Color(.separator), lineWidth: 1))
        .dropDestination(for: String.self) { items, _ in
            if let c = items.first { store.refuseDrop(c, onAct: act.id) }; return true
        }
    }
}

struct ChapterRow: View {
    @Environment(StructureStore.self) private var store
    let chapter: PChapter
    @State private var targeted = false
    var body: some View {
        Button { store.open(chapter.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(chapter.number)").font(.caption.weight(.bold)).frame(width: 26, height: 26).background(Color(.tertiarySystemFill), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) { Text(chapter.title).font(.subheadline.weight(.semibold)); if !chapter.gaps.isEmpty { Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) } }
                    Text(chapter.summary.isEmpty ? "Brief this chapter" : chapter.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.foregroundStyle(.primary)
                Spacer(minLength: 4)
                Chip(text: chapter.state.rawValue, color: stateColor(chapter.state))
            }
            .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.accentColor : (store.currentChapterID == chapter.id ? Color.accentColor.opacity(0.6) : .clear), lineWidth: 2))
        }.buttonStyle(.plain)
        .draggable(chapter.id)
        .dropDestination(for: String.self, action: { items, _ in if let c = items.first { store.move(c, onto: chapter.id) }; return true }, isTargeted: { targeted = $0 })
    }
}

// MARK: Chapter

struct ChapterView: View {
    @Environment(StructureStore.self) private var store
    let id: String
    @State private var expanded: Set<Int> = [0]
    var body: some View {
        if let c = store.chapter(id) {
            let ro = c.state == .briefed
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if c.staged { Text("Godric staged this brief. It is not committed yet: edit the fields if you like, then Commit.").font(.footnote).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 10)) }
                    HStack { Text("Chapter \(c.number)").font(.caption).foregroundStyle(.secondary); Chip(text: c.state.rawValue, color: stateColor(c.state)); Spacer() }
                    Text(c.title).font(.title3.weight(.semibold))
                    if !c.gaps.isEmpty { Label("Codex gaps: " + c.gaps.joined(separator: ", "), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SUMMARY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(c.summary.isEmpty ? "No summary yet." : c.summary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    ForEach(0..<6, id: \.self) { i in
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(i) }, set: { if $0 { expanded.insert(i) } else { expanded.remove(i) } })) {
                            if ro { Text(c.fields[i].isEmpty ? "—" : c.fields[i]).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4) }
                            else {
                                TextField(fieldNames[i], text: Binding(get: { store.chapter(id)?.fields[i] ?? "" }, set: { store.setField(id, i, $0) }), axis: .vertical)
                                    .lineLimit(2...8).padding(8).background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 4)
                            }
                        } label: { Text(fieldNames[i]).font(.subheadline.weight(.semibold)) }
                        .padding(10).background(Color(.secondarySystemBackground).opacity(ro ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if ro {
                        HStack { Button("Unlock briefing to edit") { store.unlock(id) }.buttonStyle(.bordered)
                            Button { store.say("Opens Creation on chapter \(c.number) (prototype)") } label: { Label("Draft", systemImage: "chevron.right") }.buttonStyle(.borderedProminent) }
                    } else {
                        HStack { Button { store.say("Dictation (prototype)") } label: { Label("Dictate", systemImage: "mic") }.buttonStyle(.bordered)
                            Button("Commit briefing") { store.commit(id) }.buttonStyle(.borderedProminent) }
                        Text("Saved as you leave each field. Not committed until you press Commit.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16)
            }
            .navigationTitle("Chapter \(c.number)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
                Button("Rename", systemImage: "pencil") { store.sheet = .rename(id) }
                Button("Delete…", systemImage: "trash", role: .destructive) { store.sheet = .delete(id) }
            } label: { Image(systemName: "ellipsis.circle") } } }
        } else { ContentUnavailableView("Chapter gone", systemImage: "trash") }
    }
}

// MARK: Sheets

struct AddSheet: View {
    @Environment(StructureStore.self) private var store; @Environment(\.dismiss) private var dismiss
    let actID: String; @State private var title = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Adds to the end of \(store.acts.first { $0.id == actID }?.label ?? "the act")") { TextField("Title", text: $title) }
                Section { Text("Chapters after it move up by one and their “Chapter N” labels follow. Every detail is editable afterwards.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Add chapter").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { store.add(to: actID, title: title); dismiss() } } }
        }.presentationDetents([.medium])
    }
}
struct RenameSheet: View {
    @Environment(StructureStore.self) private var store; @Environment(\.dismiss) private var dismiss
    let cid: String; @State private var title = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $title); Text("Blank becomes “Untitled chapter”.").font(.footnote).foregroundStyle(.secondary) }
                .navigationTitle("Rename chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { store.rename(cid, title); dismiss() } } }
        }.presentationDetents([.medium]).onAppear { title = store.chapter(cid)?.title ?? "" }
    }
}
struct DeleteSheet: View {
    @Environment(StructureStore.self) private var store; @Environment(\.dismiss) private var dismiss
    let cid: String; @State private var typed = ""
    var body: some View {
        let t = store.chapter(cid)?.title ?? ""
        NavigationStack {
            Form {
                Section { Text("This removes 3,200 words, 6 beats, 2 issues, 1 proof note and 4 codex links. Later chapters renumber.").font(.callout).foregroundStyle(.red) }
                Section("Type the title to confirm: \(t)") { TextField("Title", text: $typed).autocorrectionDisabled() }
                Section { Button("Delete chapter", role: .destructive) { store.delete(cid); dismiss() }.disabled(typed != t) }
            }.navigationTitle("Delete “\(t)”").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
struct StaleSheet: View {
    @Environment(StructureStore.self) private var store
    let cid: String
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Chapter \(store.chapter(cid)?.number ?? 0) was edited on the other device (14:09). Your Commit was not applied. Fields that differ:").font(.callout) }
                ForEach(store.staleDiffs) { d in
                    Section(fieldNames[d.field]) {
                        VStack(alignment: .leading) { Text("This device").font(.caption).foregroundStyle(.secondary); Text(d.mine) }
                        VStack(alignment: .leading) { Text("The other device").font(.caption).foregroundStyle(.secondary); Text(d.theirs) }
                    }
                }
                Section { Text("One choice for the whole card.").font(.footnote).foregroundStyle(.secondary)
                    Button("Use this device") { store.resolveStale(cid, useThisDevice: true) }.buttonStyle(.borderedProminent)
                    Button("Use the other device") { store.resolveStale(cid, useThisDevice: false) }.buttonStyle(.bordered) }
            }.navigationTitle("Changed elsewhere").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled()
    }
}

// MARK: Godric

struct GodricView: View {
    @Environment(StructureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var docked = false
    @State private var text = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let id = store.currentChapterID, let c = store.chapter(id) {
                    Text("Focus: Chapter \(c.number) · \(c.title)").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                } else { Text("No chapter open").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.thread) { m in
                            switch m.kind {
                            case .me: Text(m.text).padding(10).background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 14)).frame(maxWidth: .infinity, alignment: .trailing)
                            case .godric: Text(m.text).padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14)).frame(maxWidth: .infinity, alignment: .leading)
                            case .staged(let cid):
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Chapter brief staged").font(.subheadline.weight(.semibold))
                                    Text("Written onto the card. Commit it there.").font(.caption).foregroundStyle(.secondary)
                                    Button("View card ›") { dismiss(); store.open(cid) }.buttonStyle(.bordered)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            case .codex:
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Codex proposal · Cass's Honda CX (new)").font(.caption).foregroundStyle(.secondary)
                                    Text("+ A 1998 Honda CX500, dull red, never garaged.").font(.footnote).padding(4).frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.18))
                                    if let a = store.codexApplied { Text(a ? "Applied" : "Discarded").font(.caption.weight(.semibold)) }
                                    else { HStack { Button("Discard") { store.codexApplied = false }.buttonStyle(.bordered); Button("Apply") { store.codexApplied = true }.buttonStyle(.borderedProminent) } }
                                }.padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }.padding(.horizontal, 12)
                }
                HStack {
                    TextField("Message Godric", text: $text).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button { store.say("Dictation (prototype)") } label: { Image(systemName: "mic") }
                    Button("Send", action: send).disabled(text.isEmpty)
                }.padding(10)
            }
            .navigationTitle("Godric · \(store.book)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.godricOpen = false; dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
    private func send() { guard !text.isEmpty else { return }; store.send(text); text = "" }
}
