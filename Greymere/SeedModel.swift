import Foundation
import Observation

/// What the seed screen reads. Both come from the server's existing vault routes; nothing is written.
struct SeedResponse: Decodable, Sendable {
    struct Idea: Decodable, Sendable {
        let id: Int
        let title: String
        let synopsis: String?
        let developedBrief: String?
        let lastActiveAt: String?
    }
    let idea: Idea
}

struct SeedPapers: Decodable, Sendable {
    struct Paper: Decodable, Sendable, Identifiable {
        let id: Int
        let title: String
    }
    let papers: [Paper]
}

@MainActor @Observable
final class SeedModel {
    var idea: SeedResponse.Idea?
    var papers: [SeedPapers.Paper] = []
    var loading = false
    var failed = false

    func load(id: Int, using client: APIClient) async {
        loading = true
        defer { loading = false }
        do {
            let seed: SeedResponse = try await client.get("/api/vault/ideas/\(id)")
            idea = seed.idea
            failed = false
            // Research is a nicety: a failure here must not hide the seed.
            if let list: SeedPapers = try? await client.get("/api/vault/ideas/\(id)/research") { papers = list.papers }
        } catch {
            failed = true
        }
    }
}
