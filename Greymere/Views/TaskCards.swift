import SwiftUI

/// "Your tasks" as cards (0.8.0, wireframes 1 and 2): tick, size and hours, age, source; swipe right to mark done, swipe
/// left to defer; press and hold to reorder; a row to add a task, typed or dictated. Writes go through `TodayModel`
/// to the same routes the desktop Today list calls, and only for today: a past or projected day is read-only.
struct TaskCardsBlock: View {
    let model: TodayModel
    let client: APIClient
    let tasks: HomeTasks
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var detail: TaskRow?
    @State private var deferring: TaskRow?
    @State private var ticking: TaskRow?
    @State private var hoursText = ""
    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var newSize = "M"
    @State private var dictation = DictationModel()
    @FocusState private var addFocused: Bool
    @State private var pendingOrder: [Int]?
    @State private var heights: [Int: CGFloat] = [:]
    @State private var dragging: Int?
    @State private var dragY: CGFloat = 0

    private var theme: ThemeStore { connection.theme }
    private var editable: Bool { tasks.view == "today" }
    private var openRows: [TaskRow] { tasks.tasks.filter { !$0.done } }
    /// The open tasks in the order shown: the author's drop is held here until the server's answer arrives.
    private var open: [TaskRow] {
        guard let order = pendingOrder else { return openRows }
        let byID = Dictionary(uniqueKeysWithValues: openRows.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        return ordered.count == openRows.count ? ordered : openRows
    }
    private let gap: CGFloat = 8
    private var finished: [TaskRow] { tasks.tasks.filter(\.done) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(Array(open.enumerated()), id: \.element.id) { index, task in
                TaskCard(task: task, date: model.iso, editable: editable, showGrip: sizeClass == .regular,
                         lifted: dragging == task.id,
                         onTick: { startTick(task) }, onDone: { startTick(task) }, onDefer: { deferring = task },
                         onOpen: { detail = task }, onSize: { size in Task { await model.setSize(task.id, size: size, client: client) } })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[task.id] = $0 }
                    .offset(y: offset(for: task.id, at: index))
                    .zIndex(dragging == task.id ? 1 : 0)
                    .animation(dragging == task.id ? nil : .snappy(duration: 0.2), value: offset(for: task.id, at: index))
                    .gesture(editable ? reorderGesture(for: task.id) : nil)
            }
            ForEach(finished) { task in
                TaskCard(task: task, date: model.iso, editable: editable, showGrip: false,
                         onTick: { Task { await model.reopen(task.id, client: client) } }, onDone: {}, onDefer: {},
                         onOpen: { detail = task }, onSize: { _ in })
            }
            if editable { addRow }
            if let err = model.actionError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if !tasks.deferred.isEmpty {
                DeferredPanel(items: tasks.deferred, editable: editable, push: sizeClass != .regular) { id in
                    Task { await model.undefer(id, client: client) }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { addFocused = false }
            }
        }
        .task(id: connection.address) { await dictation.check(client: client) }
        .onChange(of: draft) { _, new in dictation.textChanged(to: new) }
        .onDisappear { dictation.settle(); dictation.end() }
        .alert("Hours taken", isPresented: Binding(get: { ticking != nil }, set: { if !$0 { ticking = nil } })) {
            TextField("Hours", text: $hoursText).keyboardType(.decimalPad)
            Button("Done") { if let t = ticking { finishTick(t) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ticking.map { "How long did \u{201C}\($0.title)\u{201D} take today? Leave it to keep the estimate." } ?? "")
        }
        .sheet(item: $deferring) { t in DeferSheet(task: t) { until, reason in
            Task { await model.defer_(t.id, until: until, reason: reason, client: client) }
        } }
        .sheet(item: $detail) { t in
            TaskDetail(task: t, editable: editable && !t.done,
                       onSize: { size in Task { await model.setSize(t.id, size: size, client: client) } },
                       onDone: { detail = nil; startTick(t) }, onDefer: { detail = nil; deferring = t })
                .presentationDetents([.medium])
        }
    }

    // MARK: reorder: press and hold, the card lifts a little, then it follows the finger and the others make room

    private func rowHeight(_ id: Int) -> CGFloat { (heights[id] ?? 64) + gap }

    /// Where the dragged card would land if it were dropped now.
    private func targetIndex() -> Int? {
        guard let id = dragging, let from = open.firstIndex(where: { $0.id == id }) else { return nil }
        var shift = dragY, to = from
        while shift > 0, to < open.count - 1, shift > rowHeight(open[to + 1].id) / 2 { shift -= rowHeight(open[to + 1].id); to += 1 }
        while shift < 0, to > 0, -shift > rowHeight(open[to - 1].id) / 2 { shift += rowHeight(open[to - 1].id); to -= 1 }
        return to
    }

    private func offset(for id: Int, at index: Int) -> CGFloat {
        guard let dragID = dragging, let from = open.firstIndex(where: { $0.id == dragID }), let to = targetIndex() else { return 0 }
        if id == dragID { return dragY }
        let h = rowHeight(dragID)
        if from < to, index > from, index <= to { return -h }
        if from > to, index >= to, index < from { return h }
        return 0
    }

    private func reorderGesture(for id: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging != id {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.15)) { dragging = id }
                }
                dragY = drag?.translation.height ?? 0
            }
            .onEnded { value in
                defer { withAnimation(.snappy(duration: 0.2)) { dragging = nil; dragY = 0 } }
                guard case .second(true, _) = value, let to = targetIndex(),
                      let from = open.firstIndex(where: { $0.id == id }), from != to else { return }
                var ids = open.map(\.id)
                ids.remove(at: from); ids.insert(id, at: to)
                pendingOrder = ids
                Task { await model.reorder(ids, client: client); pendingOrder = nil }
            }
    }

    private var header: some View {
        let count = tasks.view == "projected" ? "\(open.count) waiting" : tasks.view == "past" ? "\(tasks.tasks.count) done"
            : "\(open.count) to do" + (finished.isEmpty ? "" : " · \(finished.count) done today")
        let label = tasks.view == "projected" ? "Projected tasks" : tasks.view == "past" ? "Completed that day" : "Your tasks"
        return HStack {
            SectionLabel(title: label, count: nil)
            Spacer()
            Text(count).font(.caption).foregroundStyle(theme.muted)
        }
    }

    // MARK: tick, with the hours it took

    private func startTick(_ t: TaskRow) {
        guard editable, !t.done else { return }
        hoursText = t.estHours.map { Fmt.hours($0) } ?? ""
        ticking = t
    }

    private func finishTick(_ t: TaskRow) {
        let typed = hoursText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let hours = Double(typed)
        ticking = nil
        // Leaving the estimate alone sends nothing; 0 is a valid "no further hours".
        let send = (hours != nil && hours != t.estHours) ? hours : nil
        Task { await model.done(t.id, hours: send, client: client) }
    }

    // MARK: add a task

    private var addRow: some View {
        let listening = dictation.state == .listening
        let working = dictation.state == .starting || dictation.state == .stopping
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(theme.muted)
                TextField("Add a task", text: $draft, selection: $selection, axis: .vertical)
                    .focused($addFocused).submitLabel(.done)
                    .onSubmit { if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addFocused = false } else { submitAdd() } }
                if !draft.isEmpty {
                    Menu {
                        ForEach(["S", "M", "L", "XL"], id: \.self) { s in Button(s) { newSize = s } }
                    } label: {
                        Text(newSize).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: .capsule)
                    }
                    Button(action: submitAdd) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.plain).accessibilityLabel("Add task")
                }
                Button {
                    Task { await dictation.toggle(client: client, bookId: nil, field: DictationField(text: $draft, selection: $selection)) }
                } label: {
                    Image(systemName: dictation.available == false ? "mic.slash" : (listening ? "mic.fill" : "mic"))
                        .font(.title3).frame(width: 32, height: 32)
                        .foregroundStyle(listening ? AnyShapeStyle(Color.red) : AnyShapeStyle(theme.muted))
                }
                .buttonStyle(.plain).disabled(working || dictation.available == false)
                .accessibilityLabel(listening ? "Stop dictation" : "Dictate")
            }
            if let notice = dictation.notice {
                Text(notice).font(.caption).foregroundStyle(.orange).onTapGesture { dictation.notice = nil }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func submitAdd() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        dictation.settle(); dictation.end()
        draft = ""; selection = nil
        addFocused = false
        let size = newSize
        newSize = "M"
        Task { await model.add(title: title, size: size, client: client) }
    }
}

// MARK: one card

private struct TaskCard: View {
    let task: TaskRow
    let date: String
    let editable: Bool
    let showGrip: Bool
    var lifted = false
    let onTick: () -> Void
    let onDone: () -> Void
    let onDefer: () -> Void
    let onOpen: () -> Void
    let onSize: (String) -> Void
    @Environment(ConnectionModel.self) private var connection
    @State private var dx: CGFloat = 0

    private var theme: ThemeStore { connection.theme }
    private let trigger: CGFloat = 90

    var body: some View {
        ZStack {
            swipeBackdrop
            card
                .offset(x: dx)
                .simultaneousGesture(swipe)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard editable, !task.done, !lifted, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                dx = max(-140, min(140, v.translation.width))
            }
            .onEnded { v in
                let final = dx
                withAnimation(.snappy) { dx = 0 }
                guard editable, !task.done else { return }
                if final > trigger { onDone() } else if final < -trigger { onDefer() }
                _ = v
            }
    }

    private var swipeBackdrop: some View {
        HStack {
            Label("Done", systemImage: "checkmark").foregroundStyle(.green).opacity(dx > 20 ? 1 : 0)
            Spacer()
            Label("Defer", systemImage: "calendar.badge.clock").foregroundStyle(.orange).opacity(dx < -20 ? 1 : 0)
        }
        .font(.footnote.weight(.semibold)).padding(.horizontal, 16)
    }

    private var card: some View {
        let hours = task.estHours.map { est -> String in
            (task.done && task.hoursToday != nil && task.hoursToday != est) ? "took \(Fmt.hours(task.hoursToday))h" : "\(Fmt.hours(est))h"
        }
        let pushedHere = task.deferredUntil != nil && task.deferredUntil == date
        return HStack(alignment: .top, spacing: 10) {
            Button(action: onTick) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(task.done ? Color.green : theme.faint)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain).disabled(!editable)
            .accessibilityLabel(task.done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                    .strikethrough(task.done).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    if task.size == nil, task.estHours == nil, !task.done {
                        sizeMenu { Text("Needs a size").chip(fill: Color.orange.opacity(0.18), ink: .orange) }
                    } else {
                        Text([task.size, hours].compactMap { $0 }.joined(separator: " · ")).chip(fill: Color.primary.opacity(0.08), ink: theme.muted)
                    }
                    if let src = task.sourceLabel {
                        Text(src).chip(fill: theme.accent.opacity(0.14), ink: theme.accent)
                    }
                    if pushedHere {
                        Text("deferred to here" + (task.deferReason.map { " — \($0)" } ?? "")).font(.caption).foregroundStyle(.orange)
                    } else if let age = Self.age(task.generatedDate, today: date) {
                        Text(age).font(.caption).foregroundStyle(theme.muted)
                    }
                }
                if task.needsScoping == true, !task.done, let p = task.scopingPrompt {
                    Text(p).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            if showGrip && editable && !task.done {
                Image(systemName: "line.3.horizontal").foregroundStyle(theme.faint).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(lifted ? 0.22 : 0.08), radius: lifted ? 14 : 6, y: lifted ? 8 : 3)
        .scaleEffect(lifted ? 1.025 : 1)
        .opacity(task.done ? 0.7 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onOpen)
    }

    private func sizeMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            ForEach(["S", "M", "L", "XL"], id: \.self) { s in Button(s) { onSize(s) } }
        } label: { label() }
    }

    /// "Added today", "3 days ago": how long a task has been on the list.
    static func age(_ generated: String?, today: String) -> String? {
        guard let g = generated, g != today,
              let a = Self.iso.date(from: g), let b = Self.iso.date(from: today) else { return generated == nil ? nil : "Added today" }
        let days = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        if days <= 0 { return "Added today" }
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

private extension Text {
    func chip(fill: Color, ink: Color) -> some View {
        self.font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(fill, in: .capsule).foregroundStyle(ink)
    }
}

// MARK: sheets

private struct DeferSheet: View {
    let task: TaskRow
    let onDefer: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var until = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(task.title).font(.headline)
                DatePicker("Back on", selection: $until, in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                TextField("Why (optional)", text: $reason)
                    .textFieldStyle(.roundedBorder)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Defer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Defer") {
                        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                        onDefer(f.string(from: until), why.isEmpty ? nil : why)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct TaskDetail: View {
    let task: TaskRow
    let editable: Bool
    let onSize: (String) -> Void
    let onDone: () -> Void
    let onDefer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection
    /// The sheet holds the task as it was when opened, so the chosen size is kept here to show the tap at once.
    @State private var size: String

    init(task: TaskRow, editable: Bool, onSize: @escaping (String) -> Void, onDone: @escaping () -> Void, onDefer: @escaping () -> Void) {
        self.task = task; self.editable = editable; self.onSize = onSize; self.onDone = onDone; self.onDefer = onDefer
        _size = State(initialValue: task.size ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(task.title).font(.headline)
                Group {
                    Text(task.sourceLabel.map { "From \($0)" } ?? (task.origin == "author" ? "You asked for this" : "Raised by the studio"))
                    if let g = task.generatedDate { Text("On the list since \(g)") }
                    if let d = task.deferredUntil { Text("Deferred to \(d)" + (task.deferReason.map { " — \($0)" } ?? "")) }
                }
                .font(.subheadline).foregroundStyle(connection.theme.muted)
                if editable {
                    Picker("Size", selection: Binding(get: { size }, set: { if !$0.isEmpty { size = $0; onSize($0) } })) {
                        ForEach(["S", "M", "L", "XL"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        Button { onDone() } label: { Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                        Button { onDefer() } label: { Label("Defer", systemImage: "calendar.badge.clock").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// "7 deferred": expands in place on the iPad, opens its own screen on the phone, with Bring back on each row.
private struct DeferredPanel: View {
    let items: [DeferredRow]
    let editable: Bool
    let push: Bool
    let bringBack: (Int) -> Void
    @State private var open = false
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { if push { open = true } else { withAnimation(.snappy) { open.toggle() } } } label: {
                HStack(spacing: 6) {
                    Image(systemName: push ? "chevron.right" : (open ? "chevron.down" : "chevron.right")).font(.caption.weight(.semibold))
                    Text("\(items.count) deferred").font(.subheadline)
                }
                .foregroundStyle(connection.theme.muted)
            }
            .buttonStyle(.plain)
            if open && !push { rows }
        }
        .sheet(isPresented: Binding(get: { open && push }, set: { open = $0 })) {
            NavigationStack {
                ScrollView { rows.padding() }
                    .navigationTitle("Deferred").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { open = false } } }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { d in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.footnote).foregroundStyle(connection.theme.text)
                        Text("back \(d.deferredUntil ?? "")" + (d.deferReason.map { " — \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(connection.theme.muted)
                    }
                    Spacer(minLength: 0)
                    if editable { Button("Bring back") { bringBack(d.id) }.buttonStyle(.glass).font(.caption) }
                }
            }
        }
    }
}
