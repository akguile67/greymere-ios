// THROWAWAY prototype data (ADR 0.59.0 Sprint 1). Entirely invented, generated deterministically in code.
import Foundation

enum EType: String, CaseIterable, Identifiable, Hashable {
    case character, location, object, lore, voice, list, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .character: "Characters"; case .location: "Locations"; case .object: "Objects"; case .lore: "Lore"
        case .voice: "Voice guides"; case .list: "Reference lists"; case .other: "Other"
        }
    }
    var single: String {
        switch self {
        case .character: "Character"; case .location: "Location"; case .object: "Object"; case .lore: "Lore"
        case .voice: "Voice guide"; case .list: "Reference list"; case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .character: "person.fill"; case .location: "building.columns.fill"; case .object: "key.fill"; case .lore: "scroll.fill"
        case .voice: "mic.fill"; case .list: "list.bullet.rectangle.fill"; case .other: "tray.fill"
        }
    }
    /// Voice guide and reference list are fixed once set (the editing engine finds them by type).
    var locked: Bool { self == .voice || self == .list }
}

enum ImageState { case none, pending, approved }

struct Entry: Identifiable, Hashable {
    let id: Int
    var name: String
    var type: EType
    var aliases: [String]
    var body: String
    var role: String
    var parent: Int?
    var series: [String]
    var books: [String]
    var image: ImageState
    var version: Int = 1
    var edited: String = "2 h ago"
}

struct SeriesDef { let name: String; let books: [String] }

struct GapItem: Identifiable {
    enum State: Equatable { case open, created(Int), dismissed }
    let id = UUID()
    var name: String
    var type: EType
    var note: String
    var state: State
}

private struct RNG {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    mutating func chance(_ pct: Int) -> Bool { int(100) < pct }
}

enum DummyCodex {
    static let series = [
        SeriesDef(name: "The Route", books: ["Book 1 · Salt", "Book 2 · Ballast", "Book 3 · Keel"]),
        SeriesDef(name: "The Lamplit Years", books: ["Book 1 · Wick", "Book 2 · Lantern"]),
        SeriesDef(name: "Standalone", books: ["Gull Season"]),
    ]

    private static let firsts = ["Marenne","Tamsin","Edda","Ansel","Ottoline","Corwin","Isolde","Perrin","Wystan","Bryony","Hesper","Lorcan","Maud","Jory","Sabine","Fenwick","Greta","Osric","Linnet","Dunstan","Elspeth","Rufus","Thea","Caspar","Nell","Alaric","Pru","Ivo","Juniper","Barnaby"]
    private static let lasts = ["Voss","Hale","Harrow","Pryor","Pell","Marlow","Thorne","Quill","Ashby","Crane","Fenn","Gale","Holloway","Ketch","Lisle","Mercer","Noakes","Orme","Penhallow","Rook","Sallow","Tarrant","Vance","Wick","Yarrow","Dray","Keel","Bellamy","Cobb","Dunmore"]
    private static let roles = ["Captain of the Tern","Harbour clerk","Lamplighter","Housekeeper","Smuggler","Ship's surgeon","Customs officer","Net-mender","Chandler","Curate","Cartographer","Apprentice","Widow","Pilot","Innkeeper","Rival captain","Ferryman","Schoolmistress"]
    private static let buildingFirst = ["Saltgate","Wend","Ketchmoor","Pellow","Marl","Brine","Larkin","Thorn","Gull","Dunmere","Sallow","Tern","Keelhaven","Orrin","Fenwick","Rook","Vesper","Cold","Ashby","Lisle","Sparrow","Mercer","Tallow","Anchor"]
    private static let buildingKind = ["Hall","House","Quay","Lighthouse","Inn","Mill","Chapel","Rectory","Warehouse","Manor","Forge","Custom House","Chandlery"]
    private static let roomNames = ["Great Hall","Library","Kitchen","Scullery","Pantry","Study","Gallery","Chart Room","Counting House","Parlour","Attic","Loft","Boiler Room","Vestry","Tower","Armoury","Smoking Room","Ballroom","Nursery","Conservatory","Cellar","East Stair","Back Stair","Landing","Snug"]
    private static let objAdj = ["Brass","Salt-stained","Cracked","Silver","Oilskin","Ivory","Tarnished","Walnut","Ship's","Folded","Borrowed","Drowned"]
    private static let objNoun = ["compass","ledger","lantern","key","locket","knife","chart","bell","sextant","music box","letter","ring","spyglass","hourglass","chronometer","flag"]
    private static let loreA = ["Tamber","Salt","Lamp","Ballast","Gull","Tide","Harbour","Wreck","Pilot's","Widow's","Customs","Fog"]
    private static let loreB = ["Accord","Custom","Law","Rite","Treaty","Superstition","Calendar","Feud","Charter","Oath"]
    private static let sentences = [
        "The shutters on the east side are never opened.", "Everyone in Saltgate remembers the winter of the long fog.",
        "Speaks slowly, and only when a thing is worth the breath.", "Keeps a ledger no one is allowed to read.",
        "Smells of salt, damp wool and tallow.", "A clock in the hall runs four minutes slow.",
        "Was last seen on the quay the night the bell rang twice.", "Owes more than anyone knows, and to the wrong people.",
        "Prefers lamplight to daylight and says so.", "The family never speaks of the second winter.",
        "Hands cracked from rope, voice softened by years of apology.", "Built round a cold courtyard, grey sandstone, one door.",
    ]

    static func make() -> [Entry] {
        var r = RNG(s: 59_0)
        var out: [Entry] = []
        var nextID = 1
        func add(_ name: String, _ type: EType, aliases: [String] = [], role: String = "", parent: Int? = nil, body: String? = nil, series ser: [String]? = nil, books: [String]? = nil) -> Int {
            let id = nextID; nextID += 1
            let s = ser ?? [r.chance(60) ? "The Route" : (r.chance(75) ? "The Lamplit Years" : "Standalone")]
            let bks: [String]
            if let books { bks = books } else if type == .character || type == .location {
                let pool = series.filter { s.contains($0.name) }.flatMap(\.books)
                bks = pool.filter { _ in r.chance(45) }
            } else { bks = [] }
            let text = body ?? {
                var parts: [String] = []
                if type == .character, !role.isEmpty { parts.append("- **Role**: \(role)\n") }
                parts.append("**Overview**\n" + (0..<(2 + r.int(2))).map { _ in r.pick(sentences) }.joined(separator: " "))
                parts.append("**Notes**\n• " + (0..<(2 + r.int(2))).map { _ in r.pick(sentences) }.joined(separator: "\n• "))
                return parts.joined(separator: "\n\n")
            }()
            out.append(Entry(id: id, name: name, type: type, aliases: aliases, body: text, role: role, parent: parent, series: s, books: bks,
                             image: r.pick([.none, .none, .pending, .approved, .approved]), edited: r.pick(["2 h ago","yesterday","3 days ago","last week","a month ago"])))
            return id
        }

        // Hand-made anchors used in the wireframes and test script.
        _ = add("Marenne Voss", .character, aliases: ["Captain Tam", "the Captain"], role: "Captain of the Tern", series: ["The Route"], books: ["Book 1 · Salt", "Book 2 · Ballast"])
        let hall = add("Harrow Hall", .location, aliases: ["the Hall", "Old Harrow"], series: ["The Route"], books: ["Book 1 · Salt", "Book 2 · Ballast"])
        _ = add("Great Hall", .location, parent: hall, series: ["The Route"])
        let second = add("Second Floor", .location, parent: hall, series: ["The Route"])
        _ = add("The Tamarind Room", .location, aliases: ["the Orange Room"], parent: second, series: ["The Route"])
        let cellars = add("Cellars", .location, parent: hall, series: ["The Route"])
        for n in ["Wine Cellar", "Coal Cellar", "Cold Store"] { _ = add(n, .location, parent: cellars, series: ["The Route"]) }
        _ = add("East Stair", .location, parent: hall, series: ["The Route"])
        _ = add("Tamsin Hale", .character, aliases: ["Tam"], role: "Harbour clerk", series: ["The Route"])
        _ = add("Edda Harrow", .character, aliases: ["Mrs Harrow"], role: "Housekeeper", series: ["The Route"])
        _ = add("The Tamber Accord", .lore, series: ["The Route"])
        _ = add("Ansel Pryor", .character, aliases: ["Brother Ansel", "the Lamp-keeper"], role: "Lamplighter", series: ["The Route"])

        var used = Set(out.map(\.name))
        // Characters: ~98
        while out.filter({ $0.type == .character }).count < 98 {
            let n = r.pick(firsts) + " " + r.pick(lasts)
            if used.contains(n) { continue }
            used.insert(n)
            let f = n.split(separator: " ")[0], l = n.split(separator: " ")[1]
            var al: [String] = []
            if r.chance(45) { al.append(String(f.prefix(3))) }
            if r.chance(25) { al.append("\(r.pick(["Mr","Mrs","Miss","Old"])) \(l)") }
            if r.chance(15) { al.append("the " + r.pick(["Younger","Quiet","Lame","Red"])) }
            _ = add(n, .character, aliases: al, role: r.pick(roles))
        }
        // Locations: 40 buildings with floors and rooms inside (~200 contained)
        var bcount = 0
        while bcount < 40 {
            let n = r.pick(buildingFirst) + " " + r.pick(buildingKind)
            if used.contains(n) { continue }
            used.insert(n); bcount += 1
            let al = r.chance(40) ? ["the " + n.split(separator: " ").last!] : []
            let b = add(n, .location, aliases: al)
            let nRooms = r.chance(30) ? 0 : 3 + r.int(6)
            let hasFloors = nRooms > 5
            var floor: Int? = nil
            for i in 0..<nRooms {
                if hasFloors, i % 3 == 0 { floor = add(r.pick(["Ground Floor","First Floor","Second Floor","Top Floor"]) , .location, parent: b, series: out.first { $0.id == b }!.series) }
                let parent = hasFloors ? floor! : b
                let room = r.pick(roomNames)
                _ = add(room + (r.chance(30) ? " (\(n.split(separator: " ")[0]))" : ""), .location, aliases: r.chance(20) ? ["the " + room.lowercased()] : [], parent: parent, series: out.first { $0.id == b }!.series)
            }
        }
        // Objects: 61
        while out.filter({ $0.type == .object }).count < 61 {
            let n = r.pick(objAdj) + " " + r.pick(objNoun)
            if used.contains(n) { continue }
            used.insert(n)
            _ = add(n, .object, aliases: r.chance(35) ? ["the " + n.split(separator: " ").last!] : [])
        }
        // Lore: 52
        while out.filter({ $0.type == .lore }).count < 52 {
            let n = "The " + r.pick(loreA) + " " + r.pick(loreB)
            if used.contains(n) { continue }
            used.insert(n)
            _ = add(n, .lore, aliases: r.chance(30) ? [r.pick(loreA) + " rule"] : [])
        }
        for n in ["Narrator voice", "Marenne Voss — dialogue", "Tamsin Hale — letters", "Edda Harrow — speech", "Chapter-opening style", "Dialect: Saltgate"] { _ = add(n, .voice, series: ["The Route"]) }
        for n in ["Ship terms","Tide tables","Sea shanties","Naming conventions","Foods of the quay","Knots","Weather words","Currency","Church calendar","Forms of address","Sails and rigging"] { _ = add(n, .list) }
        for i in 1...19 { _ = add(r.pick(["Timeline note","Research","Map memo","Cut material","Open question","Style rule"]) + " \(i)", .other) }
        return out
    }

    static let books = series.flatMap(\.books)

    static func gaps(for book: String, entries: [Entry]) -> [GapItem] {
        let created = entries.filter { $0.type == .character }.prefix(4).map { GapItem(name: $0.name, type: .character, note: "mentioned in the synopsis", state: .created($0.id)) }
        return [
            GapItem(name: "Brother Ansel", type: .character, note: "keeps the lamp at Wend", state: .open),
            GapItem(name: "The ledger of tides", type: .object, note: "kept under the counting-house floor", state: .open),
            GapItem(name: "Wend Chapel", type: .location, note: "where the bell rang twice", state: .open),
            GapItem(name: "The Long Fog", type: .lore, note: "the winter nobody speaks of", state: .open),
            GapItem(name: "Dr Orrin Lisle", type: .character, note: "the surgeon from Keelhaven", state: .open),
            GapItem(name: "The drowned flag", type: .object, note: "found on the second tide", state: .open),
            GapItem(name: "Harbour pilot's rule", type: .lore, note: "no ship moves on a slack tide", state: .open),
        ] + created + [
            GapItem(name: "A minor cousin", type: .character, note: "named once", state: .dismissed),
            GapItem(name: "Nameless dog", type: .other, note: "mentioned in passing", state: .dismissed),
        ]
    }
}
