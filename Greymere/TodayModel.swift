import Foundation
import Observation

@MainActor @Observable
final class TodayModel {
    var date = Calendar.current.startOfDay(for: Date())
    var daily: DailyList?
    var tasks: HomeTasks?
    var flags: [FlagList.Flag] = []
    var failed = false
    private var generation = 0

    var iso: String { Self.isoFormatter.string(from: date) }
    var isToday: Bool { Calendar.current.isDateInToday(date) }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func shift(by days: Int, client: APIClient) async {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        await load(client: client)
    }

    func goToday(client: APIClient) async {
        date = Calendar.current.startOfDay(for: Date())
        await load(client: client)
    }

    /// Asks for the day on screen. A slower answer for a day the author has already left is dropped.
    func load(client: APIClient) async {
        generation += 1
        let mine = generation, day = iso
        do {
            async let d: DailyList = client.get("/api/schedule/daily-list?from=\(day)&to=\(day)")
            async let t: HomeTasks = client.get("/api/home/tasks?on=\(day)")
            let (daily, tasks) = try await (d, t)
            let flags = (try? await client.get("/api/home/flags?on=\(day)", as: FlagList.self))?.flags ?? []
            guard mine == generation else { return }
            self.daily = daily; self.tasks = tasks; self.flags = flags; failed = false
        } catch {
            guard mine == generation else { return }
            failed = true
        }
    }
}
