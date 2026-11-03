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

    // MARK: writes (0.8.0): the same routes the desktop Today list calls

    /// Why the last write failed, in the server's words; the card shows it until the next write.
    var actionError: String?

    private struct DoneBody: Encodable { let hoursToday: Double?
        enum CodingKeys: String, CodingKey { case hoursToday = "hours_today" } }
    private struct DeferBody: Encodable { let until: String; let reason: String? }
    private struct AddBody: Encodable { let title: String; let size: String? }
    private struct SizeBody: Encodable { let size: String }
    private struct ReorderBody: Encodable { let orderedIds: [Int]; let on: String
        enum CodingKeys: String, CodingKey { case orderedIds = "ordered_ids", on } }
    struct Ack: Decodable, Sendable {}

    private func write(client: APIClient, _ call: () async throws -> Void) async {
        do { try await call(); actionError = nil }
        catch let e as APIError { actionError = e.message }
        catch { actionError = "That didn't go through." }
        await load(client: client)
    }

    /// Ticks a task, with the hours it took (nil keeps the estimate).
    func done(_ id: Int, hours: Double?, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/\(id)/done", body: DoneBody(hoursToday: hours)) }
    }
    func reopen(_ id: Int, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/\(id)/reopen", body: EmptyBody()) }
    }
    func defer_(_ id: Int, until: String, reason: String?, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/\(id)/defer", body: DeferBody(until: until, reason: reason)) }
    }
    func undefer(_ id: Int, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/\(id)/undefer", body: EmptyBody()) }
    }
    func add(title: String, size: String?, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks", body: AddBody(title: title, size: size)) }
    }
    func setSize(_ id: Int, size: String, client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/\(id)/hours", body: SizeBody(size: size)) }
    }
    func reorder(_ ids: [Int], client: APIClient) async {
        await write(client: client) { let _: Ack = try await client.post("/api/home/tasks/reorder", body: ReorderBody(orderedIds: ids, on: iso)) }
    }
}
