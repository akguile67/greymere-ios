import Foundation
import Observation

/// The connection layer: remembers the server, checks it is reachable and new
/// enough, and only then lets Home load. Later screens reuse `client`.
@MainActor @Observable
final class ConnectionModel {
    enum State {
        case connecting
        case unreachable
        case tooOld(serverVersion: String)
        case ready(Instance)
    }

    /// The lowest server this app will talk to (it needs /api/home/summary).
    static let minimumServerVersion = "0.50.0"

    var state: State = .connecting
    var address: String
    let theme = ThemeStore()

    private static let defaultsKey = "greymere.serverAddress"

    init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "GreymereDefaultServerURL") as? String ?? ""
        address = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? bundled
    }

    var client: APIClient? {
        guard let url = Self.normalised(address) else { return nil }
        return APIClient(baseURL: url)
    }

    /// Connects by itself on launch; the address screen only appears if this fails.
    func connect() async {
        state = .connecting
        guard let client else { state = .unreachable; return }
        do {
            let instance: Instance = try await client.get("/api/instance")
            guard Self.version(instance.version, atLeast: Self.minimumServerVersion) else {
                state = .tooOld(serverVersion: instance.version)
                return
            }
            UserDefaults.standard.set(address, forKey: Self.defaultsKey)
            if let t: ThemeResponse = try? await client.get("/api/theme") { theme.apply(t) }
            state = .ready(instance)
        } catch {
            state = .unreachable
        }
    }

    static func normalised(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        return URL(string: s)
    }

    static func version(_ v: String, atLeast minimum: String) -> Bool {
        let a = v.split(separator: ".").map { Int($0) ?? 0 }
        let b = minimum.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }
}
