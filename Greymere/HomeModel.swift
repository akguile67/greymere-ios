import Foundation
import Observation

@MainActor @Observable
final class HomeModel {
    var summary: HomeSummary?
    var loading = false
    var failed = false

    func load(using client: APIClient) async {
        loading = true
        defer { loading = false }
        do {
            summary = try await client.get("/api/home/summary")
            failed = false
        } catch {
            failed = true
        }
    }

    var inPlan: [ShelfItem] { (summary?.shelf ?? []).filter { $0.kind == "book" && $0.state == "in_plan" } }
    var seeds: [ShelfItem] { (summary?.shelf ?? []).filter { $0.isSeed } }
    var released: [ShelfItem] { (summary?.shelf ?? []).filter { $0.state == "published" } }
    func item(_ id: String?) -> ShelfItem? { summary?.shelf.first { $0.id == id } }
}
