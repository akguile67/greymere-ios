import Foundation
import Observation

// MARK: what GET /api/planning/board returns (server 0.58.0): the desktop Kanban with each book's baseline figures

struct PlanningBoard: Decodable, Sendable {
    struct Phase: Decodable, Sendable, Identifiable {
        let key: String; let label: String; var id: String { key }
        /// The server has no label for Pre-publish yet, and sends its key.
        var title: String { key == "prepub" ? "Pre-publish" : label }
    }
    struct Step: Decodable, Sendable, Identifiable {
        let id: Int; let phase: String; let stepName: String; let sequenceOrder: Int; let isGate: Bool
    }
    struct Book: Decodable, Sendable, Identifiable {
        struct Plan: Decodable, Sendable {
            struct Window: Decodable, Sendable { let start: String?; let end: String? }
            struct StepWindow: Decodable, Sendable {
                let name: String; let status: String?
                let baselineStart: String?; let baselineEnd: String?
                let overdueDays: Int?; let rag: String?
                let progress: Double?; let expected: Double?; let driftDays: Double?
            }
            let progress: Double?
            let expected: Double?
            let rag: String?
            let driftDays: Double?
            let window: Window
            let step: StepWindow?
            let overdueSteps: Int
        }
        let id: Int
        let title: String
        let status: String
        let publishDate: String?
        let coverUrl: String?
        let currentStepId: Int?
        let currentStepName: String?
        let currentPhase: String?
        let applicableStepIds: [Int]
        let plan: Plan?
    }
    let phases: [Phase]
    let steps: [Step]
    let books: [Book]
}

/// What moving a card past unfinished work would do, as the desktop's override dialog asks it.
struct OverridePreview: Decodable, Sendable {
    struct Gate: Decodable, Sendable { struct Item: Decodable, Sendable { let itemLabel: String }; let name: String; let outstanding: [Item] }
    struct Skipped: Decodable, Sendable { let name: String; let phase: String; let status: String }
    struct Named: Decodable, Sendable { let id: Int; let name: String; let phase: String }
    let ok: Bool
    let target: Named?
    let current: Named?
    let outstandingGates: [Gate]?
    let skippedSteps: [Skipped]?
    let requiresOverride: Bool?
}

/// A drop waiting for the author to choose which step of the phase it lands on.
struct PendingStepPick: Identifiable {
    let book: PlanningBoard.Book
    let phase: PlanningBoard.Phase
    var id: String { "\(book.id)-\(phase.key)" }
}

/// A move that skips steps or a gate, waiting for the author's yes.
struct PendingOverride: Identifiable {
    let book: PlanningBoard.Book
    let step: PlanningBoard.Step
    let preview: OverridePreview
    var id: String { "\(book.id)-\(step.id)" }
}

@MainActor @Observable
final class PlanningModel {
    var board: PlanningBoard?
    var failed = false
    var banner: String?
    var picking: PendingStepPick?
    var confirming: PendingOverride?
    var busy = false

    private struct MoveBody: Encodable {
        let masterStepId: Int; let mode = "manual"; let confirmGateOverride: Bool; let overrideNote: String?
        enum CodingKeys: String, CodingKey { case masterStepId = "master_step_id", mode, confirmGateOverride = "confirm_gate_override", overrideNote = "override_note" }
    }
    private struct Moved: Decodable, Sendable { let ok: Bool? }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Follows the server's change notices (a card moved on the desktop, the plan changed) until cancelled.
    func listen(client: APIClient) async {
        for await name in ServerEvents.stream(client: client) {
            if name == "connected" { await load(client: client) }
            else if name == "planning.changed" {
                refreshTask?.cancel()
                refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    await self.load(client: client)
                }
            }
        }
    }

    func load(client: APIClient) async {
        do {
            board = try await client.get("/api/planning/board")
            failed = false
        } catch {
            if board == nil { failed = true }
        }
    }

    /// The phases the rail and columns show: every phase but Closed, and Backlog only while a book is in it.
    var phases: [PlanningBoard.Phase] {
        guard let board else { return [] }
        return board.phases.filter { p in
            p.key != "closed" && (p.key != "backlog" || board.books.contains { $0.currentPhase == "backlog" })
        }
    }

    func books(in phase: String) -> [PlanningBoard.Book] { board?.books.filter { $0.currentPhase == phase } ?? [] }

    /// The steps of a phase that this book's template has.
    func steps(in phase: String, for book: PlanningBoard.Book) -> [PlanningBoard.Step] {
        (board?.steps ?? []).filter { $0.phase == phase && book.applicableStepIds.contains($0.id) }
            .sorted { $0.sequenceOrder < $1.sequenceOrder }
    }

    func drop(_ book: PlanningBoard.Book, on phase: PlanningBoard.Phase) {
        picking = PendingStepPick(book: book, phase: phase)
    }

    /// Asks the server what the move would skip; one that skips nothing goes straight through.
    func move(_ book: PlanningBoard.Book, to step: PlanningBoard.Step, client: APIClient) async {
        picking = nil
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let preview: OverridePreview = try await client.get("/api/kanban/books/\(book.id)/override-preview?master_step_id=\(step.id)")
            if preview.ok, preview.requiresOverride == true {
                confirming = PendingOverride(book: book, step: step, preview: preview)
                return
            }
            try await perform(book, step, override: false, client: client)
        } catch let e as APIError {
            banner = e.message
        } catch {
            banner = "That move didn't go through."
        }
    }

    func confirmOverride(_ pending: PendingOverride, client: APIClient) async {
        confirming = nil
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await perform(pending.book, pending.step, override: true, client: client) }
        catch let e as APIError { banner = e.message }
        catch { banner = "That move didn't go through." }
    }

    private func perform(_ book: PlanningBoard.Book, _ step: PlanningBoard.Step, override: Bool, client: APIClient) async throws {
        let note = override ? "moved by hand from the iPad" : nil
        let _: Moved = try await client.post("/api/kanban/books/\(book.id)/move",
                                              body: MoveBody(masterStepId: step.id, confirmGateOverride: override, overrideNote: note))
        banner = nil
        await load(client: client)
    }
}
