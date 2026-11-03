import SwiftUI

/// The Planning panel (0.8.0, wireframes 3 and 4): the desktop Kanban with each book's dates and its figures against
/// the baseline. Phases are columns (three at a time on an iPad), a rail of phase chips scrolls to one, and a card is
/// held, lifted and dropped on a phase to move it by hand; most moves are automatic, so this is the exception.
struct PlanningScreen: View {
    @Bindable var model: PlanningModel
    let home: HomeModel
    let client: APIClient
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var width: CGFloat = 0
    @State private var scrollTarget: String?
    @State private var frames: [String: CGRect] = [:]
    @State private var dragging: PlanningBoard.Book?
    @State private var dragAt: CGPoint = .zero
    @State private var detail: ShelfItem?
    @State private var selectedPhase: String?

    private var theme: ThemeStore { connection.theme }
    private var visible: Int { sizeClass == .regular ? 3 : 1 }
    private let pad: CGFloat = 16
    private let gap: CGFloat = 10
    private var columnWidth: CGFloat { max((width - pad * 2 - gap * CGFloat(visible - 1)) / CGFloat(visible), 140) }

    /// The phase under the finger: a column or a chip on the rail.
    private var hover: String? {
        guard dragging != nil else { return nil }
        for (key, rect) in frames where rect.contains(dragAt) { return String(key.split(separator: ":", maxSplits: 1).last ?? "") }
        return nil
    }

    /// The phase lit as a drop target: the one under the finger, but never the phase the card already sits in.
    private var lit: String? { hover == dragging?.currentPhase ? nil : hover }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 10) {
                rail
                if model.board == nil {
                    if model.failed { Text("The board couldn't be loaded.").foregroundStyle(theme.muted).padding(.top, 40) }
                    else { ProgressView().padding(.top, 60) }
                    Spacer()
                } else if sizeClass == .regular {
                    columns
                } else {
                    phoneBody
                }
            }
            if let book = dragging {
                PlanningCard(book: book, client: client, lifted: true)
                    .frame(width: columnWidth - 16)
                    .position(x: dragAt.x, y: dragAt.y)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if let text = model.banner {
                Text(text).font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: .infinity).padding(.top, 4)
                    .onTapGesture { model.banner = nil }
                    .task(id: text) { try? await Task.sleep(for: .seconds(6)); if model.banner == text { model.banner = nil } }
            }
        }
        .coordinateSpace(name: "board")
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .background(theme.background.ignoresSafeArea())
        .topBand(true, title: "Planning")
        .glassBar(isOpen: false) { model.banner = "Godric isn't on the Planning panel yet." }
        .task { await model.load(client: client) }
        .task(id: connection.address) { await model.listen(client: client) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load(client: client) } } }
        .sheet(item: $model.picking) { pick in StepPicker(model: model, client: client, pick: pick) }
        .sheet(item: $model.confirming) { pending in OverrideSheet(model: model, client: client, pending: pending) }
        .sheet(item: $detail) { item in
            if let figures = item.detail {
                BookDetailView(item: item, figures: figures, client: client, showsBar: false, onClose: { detail = nil })
                    .presentationDetents([.large])
                    .presentationBackground(connection.theme.background)
            }
        }
    }

    // MARK: the rail: every phase, a dot where a book sits

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.phases) { phase in
                    let count = model.books(in: phase.key).count
                    let target = lit == phase.key
                    let chosen = sizeClass == .regular ? nil : currentPhaseKey
                    Button { select(phase) } label: {
                        HStack(spacing: 5) {
                            Text(phase.title).font(.footnote.weight(.semibold))
                            if count > 0 { Text("\(count)").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(theme.accent.opacity(0.18), in: .capsule).foregroundStyle(theme.accent) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(target || chosen == phase.key ? theme.accent : theme.text)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(target ? theme.accent.opacity(0.25) : nil).interactive(), in: .capsule)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { frames["chip:\(phase.key)"] = $0 }
                }
            }
            .padding(.horizontal, pad).padding(.vertical, 4)
        }
    }

    // MARK: the phone: one phase at a time, the rest listed beneath

    /// The phase on show on a phone: the author's pick, else the first phase that has a book.
    private var currentPhaseKey: String? {
        selectedPhase ?? model.phases.first(where: { !model.books(in: $0.key).isEmpty })?.key ?? model.phases.first?.key
    }

    private func select(_ phase: PlanningBoard.Phase) {
        if sizeClass == .regular { withAnimation(.snappy) { scrollTarget = phase.key } }
        else { withAnimation(.snappy) { selectedPhase = phase.key } }
    }

    private var phoneBody: some View {
        let key = currentPhaseKey ?? ""
        let here = model.books(in: key)
        let others = model.phases.filter { $0.key != key && !model.books(in: $0.key).isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let phase = model.phases.first(where: { $0.key == key }) {
                    HStack {
                        Text(phase.title).font(.title3.weight(.semibold)).foregroundStyle(theme.text)
                        Spacer()
                        Text("\(here.count)").font(.footnote).foregroundStyle(theme.muted)
                    }
                }
                if here.isEmpty {
                    Text("No books in this phase.").font(.footnote).foregroundStyle(theme.faint).padding(.vertical, 20)
                }
                ForEach(here) { book in interactive(book) }
                if dragging != nil {
                    Text("Drop on a phase above to move it").font(.footnote).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
                if !others.isEmpty {
                    Text("OTHER PHASES WITH BOOKS").font(.caption.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(theme.muted).padding(.top, 14)
                    ForEach(others) { phase in
                        Button { select(phase) } label: {
                            HStack(spacing: 4) {
                                Text(phase.title).font(.footnote.weight(.semibold))
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                            }.foregroundStyle(theme.muted)
                        }.buttonStyle(.plain)
                        ForEach(model.books(in: phase.key)) { book in interactive(book) }
                    }
                }
            }
            .padding(.horizontal, pad).padding(.bottom, 90)
        }
        .scrollDisabled(dragging != nil)
    }

    /// A card that opens its details on a tap and is held to be dragged.
    private func interactive(_ book: PlanningBoard.Book) -> some View {
        PlanningCard(book: book, client: client, lifted: false)
            .opacity(dragging?.id == book.id ? 0.3 : 1)
            .onTapGesture { openDetails(book) }
            .gesture(dragGesture(for: book))
    }

    // MARK: the columns

    private var columns: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(model.phases) { phase in column(phase).frame(width: columnWidth).id(phase.key) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, pad)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollDisabled(dragging != nil)
            .onChange(of: scrollTarget) { _, key in
                guard let key else { return }
                withAnimation(.snappy) { proxy.scrollTo(key, anchor: .leading) }
                scrollTarget = nil
            }
        }
    }

    private func column(_ phase: PlanningBoard.Phase) -> some View {
        let books = model.books(in: phase.key)
        let target = lit == phase.key
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                Spacer()
                Text("\(books.count)").font(.caption).foregroundStyle(theme.muted)
            }
            if books.isEmpty {
                Text(target ? "Drop here" : "No books").font(.footnote).foregroundStyle(theme.faint)
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            ForEach(books) { book in
                PlanningCard(book: book, client: client, lifted: false)
                    .opacity(dragging?.id == book.id ? 0.3 : 1)
                    .onTapGesture { openDetails(book) }
                    .gesture(dragGesture(for: book))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(target ? theme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular.tint(target ? theme.accent.opacity(0.22) : nil), in: .rect(cornerRadius: 16))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { frames["col:\(phase.key)"] = $0 }
    }

    // MARK: hold, lift, drop on a phase

    private func dragGesture(for book: PlanningBoard.Book) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("board")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.15)) { dragging = book }
                }
                if let loc = drag?.location { dragAt = loc }
            }
            .onEnded { value in
                defer { withAnimation(.snappy(duration: 0.2)) { dragging = nil } }
                guard case .second(true, _) = value, let key = hover,
                      let phase = model.phases.first(where: { $0.key == key }) else { return }
                model.drop(book, on: phase)
            }
    }

    private func openDetails(_ book: PlanningBoard.Book) {
        if let item = home.summary?.shelf.first(where: { $0.kind == "book" && $0.rawId == book.id }), item.hasDetails { detail = item }
    }
}

// MARK: one book's card

struct PlanningCard: View {
    let book: PlanningBoard.Book
    let client: APIClient
    var lifted = false
    @Environment(ConnectionModel.self) private var connection

    private var theme: ThemeStore { connection.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                CoverView(url: client.asset(book.coverUrl), seed: false).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let step = book.currentStepName {
                        Text(step).font(.caption).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let plan = book.plan {
                if let step = plan.step {
                    progressBar(progress: step.progress, expected: step.expected, tone: tone(step))
                    Text(window(step)).font(.caption2).foregroundStyle(theme.muted)
                } else {
                    Text("No baseline for this step").font(.caption2).foregroundStyle(theme.faint)
                }
                if let publish = PlanningFmt.short(book.publishDate) { Text("Publishes \(publish)").font(.caption2).foregroundStyle(theme.muted) }
                FlowLayout(spacing: 6) {
                    if let step = plan.step {
                        drift(step)
                        if let p = step.progress { chip("\(Int((p * 100).rounded()))%", fill: Color.primary.opacity(0.08), ink: theme.muted) }
                        if (step.overdueDays ?? 0) > 0 { chip("\(step.overdueDays!) d late", fill: Color.red.opacity(0.16), ink: .red) }
                    }
                }
            } else {
                Text("No plan yet").font(.caption2).foregroundStyle(theme.faint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(lifted ? 0.24 : 0.08), radius: lifted ? 14 : 5, y: lifted ? 8 : 2)
        .scaleEffect(lifted ? 1.03 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// This step's progress, with a tick where it should be today.
    private func progressBar(progress: Double?, expected: Double?, tone: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tone).frame(width: geo.size.width * CGFloat(min(max(progress ?? 0, 0), 1)))
                if let e = expected {
                    Rectangle().fill(theme.text).frame(width: 2, height: 10)
                        .offset(x: geo.size.width * CGFloat(min(max(e, 0), 1)) - 1)
                }
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress \(Int(((progress ?? 0) * 100).rounded())) per cent, expected \(Int(((expected ?? 0) * 100).rounded()))")
    }

    /// The dates this step is planned to run, from the baseline.
    private func window(_ step: PlanningBoard.Book.Plan.StepWindow) -> String {
        guard let a = PlanningFmt.short(step.baselineStart), let b = PlanningFmt.short(step.baselineEnd) else { return "Baseline not set" }
        return a == b ? "Planned \(a)" : "Planned \(a) – \(b)"
    }

    /// The step's standing against its baseline: red when late, amber when behind, green otherwise, grey before it starts.
    private func tone(_ step: PlanningBoard.Book.Plan.StepWindow) -> Color {
        if (step.overdueDays ?? 0) > 0 { return .red }
        if step.status == "backlog" && (step.progress ?? 0) == 0 { return Color.gray.opacity(0.55) }
        if let d = step.driftDays, d <= -0.5 { return .orange }
        return .green
    }

    /// Days against the baseline, signed: "+1.1 d vs baseline" ahead, "−2 d vs baseline" behind.
    @ViewBuilder
    private func drift(_ step: PlanningBoard.Book.Plan.StepWindow) -> some View {
        if step.status == "backlog" && (step.progress ?? 0) == 0 { chip("Not started", fill: Color.primary.opacity(0.08), ink: theme.muted) }
        if let d = step.driftDays {
            if d >= 0.5 { chip("+\(Fmt.hours(d)) d vs baseline", fill: Color.green.opacity(0.16), ink: .green) }
            else if d <= -0.5 { chip("\u{2212}\(Fmt.hours(-d)) d vs baseline", fill: Color.orange.opacity(0.2), ink: .orange) }
            else { chip("On baseline", fill: Color.green.opacity(0.16), ink: .green) }
        }
    }

    private func chip(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(fill, in: .capsule).foregroundStyle(ink)
    }
}

enum PlanningFmt {
    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let short: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"; return f
    }()
    static func short(_ date: String?) -> String? {
        guard let date, let d = iso.date(from: date) else { return nil }
        return short.string(from: d)
    }
}

// MARK: choosing the step, and confirming a move that skips work

private struct StepPicker: View {
    let model: PlanningModel
    let client: APIClient
    let pick: PendingStepPick
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        let steps = model.steps(in: pick.phase.key, for: pick.book)
        NavigationStack {
            List {
                if steps.isEmpty {
                    Text("\(pick.book.title) has no steps in \(pick.phase.title).").foregroundStyle(connection.theme.muted)
                }
                ForEach(steps) { step in
                    Button {
                        Task { await model.move(pick.book, to: step, client: client) }
                    } label: {
                        HStack {
                            Text(step.stepName).foregroundStyle(connection.theme.text)
                            if step.isGate { Image(systemName: "lock").font(.caption).foregroundStyle(connection.theme.muted) }
                            Spacer()
                            if step.id == pick.book.currentStepId { Image(systemName: "checkmark").foregroundStyle(connection.theme.accent) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Move \(pick.book.title) to \(pick.phase.title)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(connection.theme.background)
    }
}

private struct OverrideSheet: View {
    let model: PlanningModel
    let client: APIClient
    let pending: PendingOverride
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        let skipped = pending.preview.skippedSteps ?? []
        let gates = pending.preview.outstandingGates ?? []
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Moving \(pending.book.title) to \(pending.step.stepName) skips unfinished work. The move is logged as an override.")
                    .font(.subheadline).foregroundStyle(connection.theme.muted)
                if !skipped.isEmpty {
                    Text("Steps skipped").font(.footnote.weight(.semibold))
                    ForEach(skipped.indices, id: \.self) { i in
                        Text("• \(skipped[i].name) (\(skipped[i].status))").font(.footnote)
                    }
                }
                if !gates.isEmpty {
                    Text("Gates with items outstanding").font(.footnote.weight(.semibold))
                    ForEach(gates.indices, id: \.self) { i in
                        Text("• \(gates[i].name): " + gates[i].outstanding.map(\.itemLabel).joined(separator: ", ")).font(.footnote)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Text("Cancel").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                    Button { Task { await model.confirmOverride(pending, client: client) } } label: {
                        Text("Move and log override").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent)
                }
            }
            .padding()
            .navigationTitle("Skip steps?").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationBackground(connection.theme.background)
    }
}
