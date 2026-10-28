import SwiftUI

/// Today, read-only: what the day owes, what could be pulled forward, the task list, what the studio offers
/// and how full the day is. Nothing here can be ticked, deferred or added from the phone yet.
struct TodayCard: View {
    let model: TodayModel
    let client: APIClient
    var collapsed = false
    var onToggle: () -> Void = {}
    @Environment(ConnectionModel.self) private var connection

    private var theme: ThemeStore { connection.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if collapsed {
                EmptyView()
            } else if model.failed && model.tasks == nil {
                Text("Today couldn't be loaded.").foregroundStyle(theme.muted)
            } else if let tasks = model.tasks, let daily = model.daily {
                ForEach(model.flags) { flag in flagRow(flag) }
                dayItems(daily)
                taskList(tasks)
                if let studio = tasks.studio, tasks.view == "today" { studioBlock(studio) }
                if let cap = tasks.capacity { capacity(cap, view: tasks.view) }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .task { await model.load(client: client) }
    }

    // MARK: header with day arrows

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text((model.isToday ? "Today — " : "") + Self.title.string(from: model.date))
                    .font(.serif(22, relativeTo: .title3))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onToggle) {
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .foregroundStyle(theme.muted).padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Expand Today" : "Collapse Today")
            }
            if !collapsed {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button { Task { await model.shift(by: -1, client: client) } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Previous day")
                    Button("Today") { Task { await model.goToday(client: client) } }
                        .buttonStyle(.glass).disabled(model.isToday)
                    Button { Task { await model.shift(by: 1, client: client) } } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Next day")
                }
            }
        }
    }

    private static let title: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE d MMMM"; return f
    }()

    // MARK: the plan's work for the day

    @ViewBuilder
    private func dayItems(_ daily: DailyList) -> some View {
        let bucket = daily.days.first
        let cal = daily.calendar.first
        let items = bucket?.items ?? []
        let due = items.filter(\.isDue)
        let available = items.filter { !$0.isDue }
        if items.isEmpty {
            note(Self.clearNote(cal))
        } else if due.isEmpty {
            note("Nothing in the plan is due today — you're ahead on every book.", good: true)
            if !available.isEmpty { availableBlock(available) }
        } else {
            if bucket?.overcommitted == true, let b = bucket {
                note("\(Set(due.map(\.bookId)).count) books want \(Fmt.hours(b.demandHours))h of a \(Fmt.hours(b.dayCapacityHours))h day — the hours below are today's split.")
            }
            ForEach(Dictionary(grouping: due, by: \.bookId).values.sorted { ($0.first?.bookPriority ?? 0) > ($1.first?.bookPriority ?? 0) }, id: \.first?.bookId) { group in
                dueRow(group)
            }
            if !available.isEmpty { availableBlock(available) }
        }
    }

    private static func clearNote(_ cal: CalendarDay?) -> String {
        if let cal, !cal.working {
            let reason = cal.reason ?? "Off"
            if reason.lowercased().contains("holiday") { return "\(reason) — no actions today. Enjoy the break." }
            if reason == "Weekend" { return "Weekend — enjoy the day off." }
            return "\(reason) — no actions today."
        }
        return "Nothing scheduled — a clear day. Pull work forward from later in the week, or spend it on codex / voice-guide maintenance."
    }

    private func dueRow(_ group: [DayItem]) -> some View {
        let first = group[0]
        let parts = group.map { i -> String in
            if i.estimateRequired == true {
                let shown = i.needsEstimate == true ? "needs your estimate"
                    : i.capacityShared == true ? "\(Fmt.hours(i.dayHours))h of your \(Fmt.hours(i.dayHoursRequested))h estimate"
                    : "\(Fmt.hours(i.dayHours))h" + (i.estimateSize.map { " (\($0))" } ?? "") + " — your estimate"
                return "\(Fmt.activity(i)) — \(Fmt.amount(i)) · \(shown)"
            }
            var hrs = ""
            if let h = i.dayHours {
                hrs = i.capacityShared == true ? " · \(Fmt.hours(h))h of \(Fmt.hours(i.dayHoursRequested))h"
                    : " · \(Fmt.hours(h))h" + (i.hoursPerUnit.map { " (\(Fmt.hours($0))h/ch)" } ?? "")
            }
            return "\(Fmt.activity(i)) — \(Fmt.amount(i))\(hrs)"
        }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                pill("P\(first.bookPriority ?? 0)")
                Text(first.bookTitle).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
            }
            Text(parts).font(.footnote).foregroundStyle(theme.muted)
        }
    }

    private func availableBlock(_ items: [DayItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Available to pull forward", count: nil)
            ForEach(items.sorted { ($0.bookPriority ?? 0) > ($1.bookPriority ?? 0) }) { i in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        pill("P\(i.bookPriority ?? 0)")
                        Text(i.bookTitle).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                    }
                    Text("\(Fmt.activity(i)) — \(Fmt.amount(i))" + (i.dayHours.map { " · \(Fmt.hours($0))h" } ?? ""))
                        .font(.footnote).foregroundStyle(theme.muted)
                    let away = (i.daysUntilDue ?? 0) > 0
                        ? "not needed for \(i.daysUntilDue!) working day\(i.daysUntilDue == 1 ? "" : "s")" : "not yet due"
                    Text(away + (i.baselineStart.map { " · plan has it from \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(theme.faint)
                }
            }
        }
    }

    // MARK: tasks

    @ViewBuilder
    private func taskList(_ t: HomeTasks) -> some View {
        if !t.tasks.isEmpty {
            let open = t.tasks.filter { !$0.done }.count, done = t.tasks.count - open
            let label = t.view == "projected" ? "Projected task list" : t.view == "past" ? "Completed that day" : "Task list"
            let count = t.view == "projected" ? "\(open) waiting\(t.deferred.isEmpty ? "" : " · \(t.deferred.count) deferred beyond")"
                : t.view == "past" ? "\(t.tasks.count) done"
                : "\(open) to do" + (done > 0 ? " · \(done) done today" : "")
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionLabel(title: label, count: nil); Spacer(); Text(count).font(.caption).foregroundStyle(theme.muted) }
                ForEach(t.tasks) { task in taskRow(task, date: model.iso) }
            }
        }
        if !t.deferred.isEmpty { DeferredList(items: t.deferred) }
    }

    private func taskRow(_ t: TaskRow, date: String) -> some View {
        let hours = t.estHours.map { est -> String in
            (t.done && t.hoursToday != nil && t.hoursToday != est) ? "\(Fmt.hours(t.hoursToday))h of \(Fmt.hours(est))h" : "\(Fmt.hours(est))h"
        } ?? "—"
        let pushedHere = t.deferredUntil != nil && t.deferredUntil == date
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(t.done ? Color.green : theme.faint).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(.subheadline).foregroundStyle(theme.text).strikethrough(t.done)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 8) {
                    Text(t.size ?? "?").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                    Text(hours).font(.caption).foregroundStyle(theme.muted)
                    Text(t.sourceLabel.map { "from \($0)" } ?? (t.origin == "author" ? "you asked" : "studio raised"))
                        .font(.caption).foregroundStyle(theme.muted)
                    if pushedHere {
                        Text("deferred to here" + (t.deferReason.map { " — \($0)" } ?? "")).font(.caption).foregroundStyle(.orange)
                    } else if let g = t.generatedDate, g != date {
                        Text("since \(g)").font(.caption).foregroundStyle(theme.muted)
                    }
                }
                if t.needsScoping == true, !t.done, let p = t.scopingPrompt {
                    Text(p).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: studio offers, capacity, flags

    private func studioBlock(_ s: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let m = s.message { note(m, good: true) }
            if !s.areas.isEmpty {
                SectionLabel(title: "On offer from the studio", count: nil)
                ForEach(s.areas) { a in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            pill(a.label)
                            if let more = a.more, more > 0 { Text("\(more) more waiting").font(.caption).foregroundStyle(theme.faint) }
                        }
                        Text(a.item.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                        let basis = ["set": "your size", "default": "default size for its type", "unsized": "not sized"][a.item.sizeBasis ?? ""] ?? ""
                        let hrs = a.item.sizeHours.map { "\(Fmt.hours($0))h" } ?? "unsized"
                        Text("From \(a.item.source ?? a.label) — \(a.item.reason ?? "") · \(hrs) (\(basis))" + (a.item.pinned == true ? " · pinned" : ""))
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func capacity(_ c: Capacity, view: String) -> some View {
        if !c.isWorkingDay {
            note("Not a working day — nothing is committed against today.")
        } else {
            let pct = c.availableHours > 0 ? min(1, c.committedHours / c.availableHours) : 0
            let gaps = [
                (c.unsizedTasks ?? 0) > 0 ? "\(c.unsizedTasks!) unsized" : nil,
                (c.unestimatedDays ?? 0) > 0 ? "\(c.unestimatedDays!) editing day\(c.unestimatedDays == 1 ? "" : "s") unpriced" : nil,
            ].compactMap { $0 }
            let free = max(0, c.availableHours - c.committedHours)
            let advice = c.overCapacity
                ? (view == "projected"
                    ? "Projected \(Fmt.hours(c.overByHours))h over. Deferring into this day is what puts it here."
                    : "Over by \(Fmt.hours(c.overByHours))h. Something needs to move — defer a task, or ask Godric to re-order the list.")
                : gaps.isEmpty ? "\(Fmt.hours((free * 10).rounded() / 10))h still free." : "This total is incomplete — \(gaps.joined(separator: " and ")) still to price."
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Fmt.hours(c.committedHours))h").font(.title3.weight(.semibold)).foregroundStyle(theme.text)
                    Text("committed of \(Fmt.hours(c.availableHours))h available" + (gaps.isEmpty ? "" : " + \(gaps.joined(separator: ", "))"))
                        .font(.footnote).foregroundStyle(theme.muted)
                }
                ProgressView(value: pct).tint(c.overCapacity ? .red : theme.accent)
                Text(advice).font(.caption).foregroundStyle(c.overCapacity ? Color.red : theme.muted)
                Text("\(Fmt.hours(c.scheduledHours))h scheduled production · \(Fmt.hours(c.taskHours))h tasks"
                     + ((c.doneHours ?? 0) > 0 ? " (\(Fmt.hours(c.doneHours))h of that done)" : ""))
                    .font(.caption).foregroundStyle(theme.faint)
            }
        }
    }

    private func flagRow(_ f: FlagList.Flag) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(f.text).font(.subheadline).foregroundStyle(theme.text)
        }
    }

    // MARK: small pieces

    private func note(_ text: String, good: Bool = false) -> some View {
        Text(text).font(.subheadline).foregroundStyle(good ? Color.green : theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(theme.accent.opacity(0.15), in: .capsule).foregroundStyle(theme.accent)
    }
}

/// "5 deferred", closed until tapped, as on the desktop.
private struct DeferredList: View {
    let items: [DeferredRow]
    @State private var open = false
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                    Text("\(items.count) deferred").font(.subheadline)
                }
                .foregroundStyle(connection.theme.muted)
            }
            .buttonStyle(.plain)
            if open {
                ForEach(items) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.footnote).foregroundStyle(connection.theme.text)
                        Text("back \(d.deferredUntil ?? "")" + (d.deferReason.map { " — \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(connection.theme.muted)
                    }
                }
            }
        }
    }
}
