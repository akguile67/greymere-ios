import Foundation

enum APIError: Error {
    case unreachable
    case badStatus(Int)
    case unreadable
    case http(Int, String)

    /// What the server said went wrong, in its own words (`{"error": "…"}`), or a plain reason.
    var message: String {
        switch self {
        case .http(let code, let body):
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["error"] as? String, !text.isEmpty { return text }
            return "Server error \(code)"
        case .unreachable: return "Could not reach the server. Check that Tailscale is on."
        case .badStatus(let code): return "Server error \(code)"
        case .unreadable: return "The server's answer could not be read."
        }
    }
}

/// A request that sends nothing but `{}`.
struct EmptyBody: Encodable, Sendable {}

/// The one place the app talks to the server. GET for everything it reads; POST for Godric chat (0.3.0) and the Ideation synopsis actions (0.5.0), PATCH to save a hand edit.
struct APIClient: Sendable {
    let baseURL: URL

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.unreachable }
        let data: Data, response: URLResponse
        do { (data, response) = try await Self.session.data(from: url) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.unreadable }
    }

    /// A server path (a cover) made into a full address.
    func asset(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// A chat turn can run for minutes (Godric works through tools before he answers), so it gets its own patience.
    private static let chatSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        try await send("POST", path, body: body)
    }

    /// Saving the synopsis by hand (0.5.0): the only PATCH the app makes.
    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        try await send("PATCH", path, body: body)
    }

    private func send<B: Encodable, T: Decodable>(_ method: String, _ path: String, body: B) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        request.httpBody = try? encoder.encode(body)
        let data: Data, response: URLResponse
        do { (data, response) = try await Self.chatSession.data(for: request) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.unreadable }
    }
}
