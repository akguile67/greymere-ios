import Foundation

/// The server's "something changed" channel (`/api/events`). Yields each event's name, and "connected" every time the
/// stream opens (first time or after a drop), because events missed while it was down are not replayed.
enum ServerEvents {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 24 * 3600
        c.timeoutIntervalForResource = 24 * 3600
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func stream(client: APIClient) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                guard let url = URL(string: "/api/events", relativeTo: client.baseURL) else { continuation.finish(); return }
                while !Task.isCancelled {
                    do {
                        var request = URLRequest(url: url)
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await session.bytes(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.unreachable }
                        continuation.yield("connected")
                        for try await line in bytes.lines where line.hasPrefix("event:") {
                            continuation.yield(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                        }
                    } catch {
                        if Task.isCancelled { break }
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
