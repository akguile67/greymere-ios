import Foundation

// The Today card reads three calls the desktop Home already makes, so the two cannot disagree.

struct DailyList: Decodable, Sendable {
    let days: [DayBucket]
    let calendar: [CalendarDay]
}
struct CalendarDay: Decodable, Sendable { let date: String; let working: Bool; let reason: String? }
struct DayBucket: Decodable, Sendable {
    let date: String
    let items: [DayItem]
    let dayCapacityHours: Double?
    let demandHours: Double?
    let overcommitted: Bool?
}
struct DayItem: Decodable, Sendable, Identifiable {
    let bookId: Int
    let bookTitle: String
    let bookPriority: Int?
    let phase: String
    let stepName: String?
    let actLabel: String?
    let cycleNumber: Int?
    let cycleStep: String?
    let unit: String?
    let allocated: Double?
    let dayHours: Double?
    let dayHoursRequested: Double?
    let capacityShared: Bool?
    let hoursPerUnit: Double?
    let estimateRequired: Bool?
    let needsEstimate: Bool?
    let estimateSize: String?
    let due: Bool?
    let isOverride: Bool?
    let daysUntilDue: Int?
    let baselineStart: String?
    var id: String { "\(bookId)-\(phase)-\(stepName ?? "")-\(actLabel ?? "")" }
    var isDue: Bool { due != false }
}

struct HomeTasks: Decodable, Sendable {
    let view: String                 // "today", "projected" or "past"
    let tasks: [TaskRow]
    let deferred: [DeferredRow]
    let capacity: Capacity?
    let studio: Studio?
}
struct TaskRow: Decodable, Sendable, Identifiable {
    let id: Int
    let origin: String?
    let title: String
    let size: String?
    let estHours: Double?
    let hoursToday: Double?
    let generatedDate: String?
    let deferredUntil: String?
    let deferReason: String?
    let done: Bool
    let sourceLabel: String?
    let needsScoping: Bool?
    let scopingPrompt: String?
}
struct DeferredRow: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let deferredUntil: String?
    let deferReason: String?
}
struct Capacity: Decodable, Sendable {
    let availableHours: Double
    let scheduledHours: Double
    let taskHours: Double
    let doneHours: Double?
    let committedHours: Double
    let overByHours: Double?
    let overCapacity: Bool
    let isWorkingDay: Bool
    let unsizedTasks: Int?
    let unestimatedDays: Int?
}
struct Studio: Decodable, Sendable {
    struct Area: Decodable, Sendable, Identifiable {
        struct Item: Decodable, Sendable {
            let title: String
            let source: String?
            let reason: String?
            let sizeHours: Double?
            let sizeBasis: String?
            let pinned: Bool?
        }
        let id: String
        let label: String
        let item: Item
        let more: Int?
    }
    let areas: [Area]
    let message: String?
}
struct FlagList: Decodable, Sendable {
    struct Flag: Decodable, Sendable, Identifiable { let key: String; let text: String; var id: String { key } }
    let flags: [Flag]
}
