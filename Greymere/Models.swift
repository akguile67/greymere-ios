import Foundation

struct Instance: Decodable, Sendable {
    let environment: String
    let version: String
}

struct ThemeResponse: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let primary: String
        let accent: String
        let background: String
        let surface: String
        let text: String
        let textMuted: String
        let textFaint: String
    }
    struct Selection: Decodable, Sendable { let variant: String }
    let theme: Tokens
    let selection: Selection
}

struct HomeSummary: Decodable, Sendable {
    let generatedAt: String
    let cards: [Card]
    let shelf: [ShelfItem]
}

struct Card: Decodable, Identifiable, Sendable {
    let cardKey: String
    let rag: String
    let comment: String
    var id: String { cardKey }
}

struct ShelfItem: Decodable, Identifiable, Sendable {
    let kind: String            // "book" or "idea" (a seed)
    let rawId: Int
    let title: String
    let state: String           // "in_plan", "published" or "idea"
    let status: String?
    let coverUrl: String?
    let hasPlan: Bool?
    let publishDate: String?
    let phase: String?
    let stepName: String?
    let activityAt: String?
    let detail: BookFigures?

    var id: String { "\(kind)-\(rawId)" }
    private enum CodingKeys: String, CodingKey {
        case kind, rawId = "id", title, state, status, coverUrl, hasPlan, publishDate
        case phase, stepName, activityAt, detail
    }

    var isSeed: Bool { kind == "idea" || state == "idea" }
    /// Book Details is for a released book or one with a plan, never a seed.
    var hasDetails: Bool { kind == "book" && detail != nil && (state == "published" || hasPlan == true) }
}

struct NextMilestone: Decodable, Sendable { let name: String; let date: String; let daysAway: Int }
struct CurrentStep: Decodable, Sendable { let name: String?; let date: String?; let workingDaysUntil: Double?; let band: String? }
struct OverdueStep: Decodable, Sendable, Identifiable {
    let stepName: String
    let daysLate: Int
    let awaitsConfirmation: Bool
    var id: String { stepName }
}

/// What Book Details shows. Every figure is the server's, shown as sent.
struct BookFigures: Decodable, Sendable {
    let id: Int
    let title: String
    let status: String
    let seriesName: String?
    let publishDate: String?
    let health: String?
    let planDriftDays: Double?
    let nextMilestone: NextMilestone?
    let currentStep: CurrentStep?
    let overdueSteps: [OverdueStep]
    let template: String?
    let priority: Int?
    let schedulingMode: String?
    let daysSlack: Double?
    let contingency: Double?
    let chapterTarget: Int?
    let synopsis: String?
    let chapterCount: Int?
    let chaptersDone: Int?
    let wordCount: Int?
    let wordTarget: Int?
    let openIssues: Int?
}
