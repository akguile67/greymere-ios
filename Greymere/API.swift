import Foundation

enum APIError: Error {
    case unreachable
    case badStatus(Int)
    case unreadable
}

/// The one place the app talks to the server. Read-only in 0.1.0: GET and nothing else.
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
}
