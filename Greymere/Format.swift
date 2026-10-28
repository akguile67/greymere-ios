import Foundation

/// Words and numbers the way the desktop writes them. Display only: no figure is worked out here.
enum Fmt {
    static func signed(_ n: Double?, unit: String) -> String {
        guard let n else { return "—" }
        let body = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
        return (n > 0 ? "+" : "") + body + unit
    }

    static func number(_ n: Int?) -> String {
        guard let n else { return "—" }
        return n.formatted(.number.grouping(.automatic))
    }

    /// "2027-02-27" → "27 Feb 2027"
    static func date(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_GB")))
    }

    /// The shelf's "Today / 8 days ago", as the desktop words it.
    static func when(_ ts: String?) -> String {
        guard let ts, !ts.isEmpty else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let t = f.date(from: String(ts.replacingOccurrences(of: "T", with: " ").prefix(19))) else { return "" }
        let days = Int(Date().timeIntervalSince(t) / 86400)
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 14 { return "\(days) days ago" }
        if days < 60 { return "\(days / 7) weeks ago" }
        return "\(days / 30) months ago"
    }

    static func stateLabel(_ it: ShelfItem) -> String {
        if it.state == "published" { return "Released" }
        if it.isSeed { return "Seed" }
        return it.stepName ?? "In plan"
    }

    static func phase(_ status: String) -> String {
        switch status {
        case "idea": return "Seed"
        case "publish", "published": return "Published"
        default: return status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    /// The series line the desktop shows over the title.
    static func seriesLine(template: String?, series: String?) -> String {
        switch template {
        case "Greymere Novella": return "Greymere Novellas"
        case "Greymere Crime Novel": return "Greymere Crime Novels"
        case "Greymere Historical Novel": return "Greymere Historical"
        default: return series ?? template ?? ""
        }
    }

    static func environmentName(_ env: String) -> String {
        switch env {
        case "production": return "PROD"
        case "pre-production": return "PRE-PROD"
        default: return "DEV"
        }
    }

    /// 6 → "6", 2.5 → "2.5"
    static func hours(_ h: Double?) -> String {
        guard let h else { return "—" }
        return h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)
    }

    /// "Draft A1", "Edit C2·P1", "Produce: Final adjustments", as the desktop words a planned step.
    static func activity(_ i: DayItem) -> String {
        let names = ["ideation": "Ideate", "drafting": "Draft", "editing": "Edit", "proofreading": "Proofread",
                     "production": "Produce", "marketing": "Market", "published": "Publish", "review": "Review", "planning": "Plan"]
        let base = names[i.phase] ?? i.phase
        var suffix = ""
        if let act = i.actLabel, !act.isEmpty {
            if let m = act.range(of: #"^Act\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]) {
                suffix = " A" + act[m].filter(\.isNumber)
            } else if act.lowercased().hasPrefix("prologue") { suffix = " Pro" }
            else if act.lowercased().hasPrefix("epilogue") { suffix = " Epi" }
            else { suffix = " " + act }
        } else if let c = i.cycleNumber, let step = i.cycleStep {
            suffix = " C\(c)·" + (step == "pass1" ? "P1" : step == "pass2" ? "P2" : step)
        }
        let label = base + suffix
        if i.isOverride == true || i.stepName == nil || (i.actLabel ?? "") != "" || (i.cycleNumber != nil && i.cycleStep != nil) { return label }
        return "\(label): \(i.stepName!)"
    }

    static func amount(_ i: DayItem) -> String {
        let n = i.allocated.map { Fmt.hours($0) } ?? "—"
        if i.unit == "phase-day" { return "1 day" }
        return "\(n) " + (i.unit == "issues" ? "issues" : "ch")
    }
}
