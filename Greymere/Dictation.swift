import AVFoundation
import Foundation
import Observation
import SwiftUI

// Dictation (ADR 0.53.0, docs/dictation-exit-checklist.md). The app captures the microphone, streams it to the
// server and shows the text that comes back. The model, the spelling prompt and the corrections all live on the
// server; the app holds no vocabulary and calls no AI service.

/// What the server sends on a dictation stream (`src/dictation-routes.js`): pending text can still revise, fixed text
/// is final, `stopped` ends the stream.
struct DictationEvent: Decodable, Sendable {
    let type: String
    let text: String?
    let reason: String?
    let message: String?
    let subs: [DictationSub]?
}

/// A word the server changed (applied) or left alone but could have changed (suggested). `start`/`end` are UTF-16
/// offsets into the event's text, as the server counts them. `id` is nil for a Codex-name snap.
struct DictationSub: Decodable, Sendable {
    let id: Int?
    let state: String
    let heard: String
    let intended: String
    let start: Int
    let end: Int
}

/// One chip under the draft: a change to undo, a suggestion to accept, or a correction just learned.
struct DictationChip: Identifiable, Equatable {
    enum Kind { case applied, suggested, learned }
    let id = UUID()
    let kind: Kind
    let serverId: Int?
    let heard: String
    let intended: String
    var at: Int                     // character offset in the draft; -1 for a learned chip
    var created = false

    var label: String {
        switch kind {
        case .applied: "\(heard) → \(intended)  Undo"
        case .suggested: "\(heard)? Use \(intended)"
        case .learned: "Remembered \(heard) → \(intended)  ✕"
        }
    }
}

private struct LearnEdit: Codable, Sendable { let heard: String; let intended: String }
private struct LearnRequest: Encodable { let bookId: Int?; let edits: [LearnEdit] }
private struct Learned: Decodable, Sendable { let id: Int; let heard: String; let intended: String; let created: Bool }
private struct LearnReply: Decodable, Sendable { let learned: [Learned] }
private struct KeepRequest: Encodable { let bookId: Int?; let heard: String }

private struct DictationStatus: Decodable, Sendable { let modelPresent: Bool; let binary: String? }
private struct SessionRequest: Encodable { let bookId: Int? }
private struct SessionReply: Decodable, Sendable { let id: String }
private struct Empty: Encodable {}
private struct Ignored: Decodable, Sendable {}

extension APIClient {
    private static let audioSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// The text stream stays open through long pauses, so it is patient where the other requests are not.
    private static let streamSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3600
        c.timeoutIntervalForResource = 4 * 3600
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// A request whose answer does not matter (undo, keep, forget): fire and forget, errors dropped.
    func fire(_ method: String, _ path: String, body: Data? = nil) {
        guard let url = URL(string: path, relativeTo: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        Task { _ = try? await Self.audioSession.data(for: request) }
    }

    /// One chunk of audio: raw mono 16-bit PCM at 16 kHz.
    func postAudio(_ path: String, data: Data) async throws {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let response: URLResponse
        do { (_, response) = try await Self.audioSession.data(for: request) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }

    /// The server-sent event stream of one dictation session.
    func dictationEvents(_ path: String) -> AsyncThrowingStream<DictationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.unreachable }
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await Self.streamSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.unreachable }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        if let data = line.dropFirst(6).data(using: .utf8),
                           let event = try? JSONDecoder().decode(DictationEvent.self, from: data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The microphone, resampled to mono 16-bit PCM at 16 kHz and handed out in small chunks. Nothing is written to disk.
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    let chunks: AsyncStream<Data>
    private let sink: AsyncStream<Data>.Continuation

    init() {
        var continuation: AsyncStream<Data>.Continuation!
        chunks = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        sink = continuation
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Measurement mode leaves the level alone (no automatic gain), which the server's silence filter is tuned for.
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "Greymere.Dictation", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in self?.convert(buffer) }
        engine.prepare()
        try engine.start()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
        sink.yield(Data(bytes: channel[0], count: Int(out.frameLength) * 2))
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The text field dictation writes into: the draft and where the caret is.
struct DictationField {
    let text: Binding<String>
    let selection: Binding<TextSelection?>
}

@MainActor @Observable
final class DictationModel {
    enum State: Equatable { case idle, starting, listening, stopping }

    private(set) var state: State = .idle
    /// nil until the server has been asked. false when it cannot dictate (too old, no model, unreachable).
    private(set) var available: Bool?
    /// A short plain message for the author: why dictation did not start, or why it stopped.
    var notice: String?

    var isActive: Bool { state != .idle }

    // The dictation point (see the desktop page): where the last dictated words ended. Moving the caret does not move
    // it; the author's own edits shift it. `live` is the open run, replaced by each revision; `adopted` counts words of
    // the open window the author has edited, which are his from then on.
    @ObservationIgnored private var field: DictationField?
    @ObservationIgnored private var anchor = 0
    @ObservationIgnored private var live = ""
    @ObservationIgnored private var lastValue = ""
    @ObservationIgnored private var adopted = 0

    // Chips and learning (checklist E, F). `learnField` outlives dictation so a chip still works after it stops.
    private(set) var chips: [DictationChip] = []
    @ObservationIgnored private var learnField: DictationField?
    @ObservationIgnored private var bookId: Int?
    @ObservationIgnored private var snapshot = ""
    @ObservationIgnored private var segments: [(at: Int, text: String)] = []
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var mic: MicCapture?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var eventsEnded = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // MARK: availability

    /// Asks the server whether it can dictate. Quiet: only sets `available`.
    func check(client: APIClient) async {
        do {
            let status: DictationStatus = try await client.get("/api/dictation/status")
            available = status.modelPresent && status.binary != nil
        } catch {
            available = false
        }
    }

    // MARK: start and stop

    func toggle(client: APIClient, bookId: Int?, field: DictationField) async {
        switch state {
        case .listening: await stop()
        case .idle: await start(client: client, bookId: bookId, field: field)
        default: break
        }
    }

    private func start(client: APIClient, bookId: Int?, field: DictationField) async {
        notice = nil
        // The permission prompt appears the first time the button is tapped, never at launch.
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            notice = "The microphone is off for Greymere. Turn it on in Settings, Privacy, Microphone."
            return
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                notice = "Dictation needs the microphone. You can turn it on in Settings, Privacy, Microphone."
                return
            }
        default: break
        }
        state = .starting
        do {
            let status: DictationStatus = try await client.get("/api/dictation/status")
            available = status.modelPresent && status.binary != nil
            guard available == true else { notice = "This server cannot dictate yet."; state = .idle; return }
        } catch APIError.badStatus {
            available = false
            notice = "This server is too old for dictation."
            state = .idle
            return
        } catch {
            available = false
            notice = "Dictation needs the server and Tailscale."
            state = .idle
            return
        }
        do {
            let reply: SessionReply = try await client.post("/api/dictation/sessions", body: SessionRequest(bookId: bookId))
            sessionID = reply.id
            self.client = client
            self.field = field
            self.learnField = field
            self.bookId = bookId
            lastValue = field.text.wrappedValue
            live = ""
            adopted = 0
            anchor = caretOffset(in: lastValue) ?? lastValue.count
            eventsEnded = false

            let capture = MicCapture()
            try capture.start()
            mic = capture
            beginEvents(client: client, id: reply.id)
            beginSending(client: client, id: reply.id, capture: capture)
            watchInterruptions()
            state = .listening
        } catch {
            teardown()
            notice = "Dictation could not start."
        }
    }

    /// The author's own stop: what is left is transcribed and fixed as it stands.
    func stop() async {
        guard state == .listening, let client, let id = sessionID else { return }
        state = .stopping
        mic?.stop()
        mic = nil
        await sendTask?.value
        let _: Ignored? = try? await client.post("/api/dictation/sessions/\(id)/stop", body: Empty())
        for _ in 0..<80 where !eventsEnded && state == .stopping { try? await Task.sleep(for: .milliseconds(50)) }
        finish()
    }

    /// Ends dictation at once and keeps whatever is in the field as ordinary typed text. Used when the message is sent,
    /// the app leaves the foreground, the chat closes, an interruption comes in or the connection drops.
    func end(notice message: String? = nil) {
        guard state != .idle else { return }
        if let client, let id = sessionID {
            Task { let _: Ignored? = try? await client.post("/api/dictation/sessions/\(id)/stop", body: Empty()) }
        }
        if let message { notice = message }
        teardown()
    }

    private func finish() {
        teardown()
    }

    private func teardown() {
        mic?.stop()
        mic = nil
        sendTask?.cancel(); sendTask = nil
        eventsTask?.cancel(); eventsTask = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        sessionID = nil
        field = nil
        live = ""
        adopted = 0
        state = .idle
    }

    // MARK: audio out, text in

    private func beginSending(client: APIClient, id: String, capture: MicCapture) {
        sendTask = Task { [weak self] in
            var pending = Data()
            var failures = 0
            func send(_ data: Data) async -> Bool {
                do { try await client.postAudio("/api/dictation/sessions/\(id)/audio", data: data); failures = 0; return true }
                catch { failures += 1; return failures < 5 }
            }
            for await chunk in capture.chunks {
                pending.append(chunk)
                if pending.count >= 8000 {                     // about a quarter of a second
                    let ok = await send(pending)
                    pending.removeAll(keepingCapacity: true)
                    if !ok { await self?.end(notice: "Dictation stopped: the connection dropped."); return }
                }
            }
            if !pending.isEmpty { _ = await send(pending) }
        }
    }

    private func beginEvents(client: APIClient, id: String) {
        eventsTask = Task { [weak self] in
            do {
                for try await event in client.dictationEvents("/api/dictation/sessions/\(id)/events") {
                    await self?.handle(event)
                }
                await self?.eventsDidEnd(dropped: false)
            } catch {
                await self?.eventsDidEnd(dropped: true)
            }
        }
    }

    private func eventsDidEnd(dropped: Bool) {
        eventsEnded = true
        if dropped, state == .listening { end(notice: "Dictation stopped: the connection dropped.") }
        else if state == .listening { end() }
    }

    private func watchInterruptions() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] n in
            let began = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor in self?.end(notice: "Dictation stopped: something else took the microphone.") } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if reason { Task { @MainActor in self?.end(notice: "Dictation stopped: the microphone was unplugged.") } }
        })
    }

    private func handle(_ event: DictationEvent) {
        guard field != nil else { return }
        switch event.type {
        case "pending": write(event.text ?? "", fixed: false)
        case "fixed": write(event.text ?? "", fixed: true, subs: event.subs ?? [])
        case "error":
            write("", fixed: false)
            notice = "Dictation had a problem and may have missed some words."
        case "stopped":
            write("", fixed: false)
            finish()
        default: break
        }
    }

    // MARK: the dictation point

    /// The author edited the field. An edit before the dictation point moves it; an edit inside the open run makes
    /// those words his, so later revisions of them are ignored. Edits inside dictated text are learned once they settle.
    func textChanged(to new: String) {
        guard field != nil || learnField != nil, new != lastValue else { return }
        let a = Array(lastValue), b = Array(new)
        var p = 0
        while p < min(a.count, b.count), a[p] == b[p] { p += 1 }
        var sa = a.count, sb = b.count
        while sa > p, sb > p, a[sa - 1] == b[sb - 1] { sa -= 1; sb -= 1 }
        if field != nil {
            let liveCount = live.count
            if sa <= anchor {
                anchor += sb - sa
            } else if p < anchor + liveCount {
                adopted += live.split(whereSeparator: \.isWhitespace).count
                anchor = min(b.count, anchor + liveCount + (sb - sa))
                live = ""
            }
        }
        lastValue = new

        if new.isEmpty {                                 // sent or cleared: nothing left to undo or learn from
            chips = []; segments = []; snapshot = ""; dirty = false
            settleTask?.cancel(); settleTask = nil
            return
        }
        shiftChips(editStart: p, editEnd: sa, delta: sb - sa)
        if !segments.isEmpty {
            dirty = true
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { self?.settle() }
            }
        }
    }

    private func caretOffset(in text: String) -> Int? {
        guard let selection = (field ?? learnField)?.selection.wrappedValue else { return nil }
        if case .selection(let range) = selection.indices, range.lowerBound <= text.endIndex {
            return text.distance(from: text.startIndex, to: range.lowerBound)
        }
        return nil
    }

    /// Keeps only what comes after the words the author has taken over.
    private func afterAdopted(_ text: String) -> String {
        guard adopted > 0, !text.isEmpty else { return text }
        var left = adopted
        var cut = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            if i == text.endIndex || left == 0 { break }
            while i < text.endIndex, !text[i].isWhitespace { i = text.index(after: i) }
            cut = i
            left -= 1
        }
        return String(text[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ incoming: String, fixed: Bool, subs: [DictationSub] = []) {
        guard let field else { return }
        if fixed && dirty { settle() }                    // an edit made before this segment arrived is learned first
        let text = afterAdopted(incoming)
        var chars = Array(field.text.wrappedValue)
        if field.text.wrappedValue != lastValue { live = ""; anchor = min(anchor, chars.count) }   // changed behind our back
        var liveChars = Array(live)
        if !liveChars.isEmpty {
            let stillThere = anchor + liveChars.count <= chars.count && Array(chars[anchor..<(anchor + liveChars.count)]) == liveChars
            if !stillThere { live = ""; liveChars = [] }
        }
        let at = min(anchor, chars.count)
        let end = at + liveChars.count
        let caret = caretOffset(in: field.text.wrappedValue) ?? end
        let before = Array(chars[..<at])
        let lead = (!text.isEmpty && !before.isEmpty && !(before.last!.isWhitespace)) ? " " : ""
        let ins = text.isEmpty ? "" : lead + text
        chars = before + Array(ins) + Array(chars[end...])
        let new = String(chars)

        // The caret stays with the text if it was at the dictation point; otherwise it stays where the author put it.
        let follows = caret >= at && caret <= end
        let newCaret = follows ? at + ins.count : (caret > end ? caret + ins.count - (end - at) : caret)

        field.text.wrappedValue = new
        let clamped = max(0, min(newCaret, chars.count))
        field.selection.wrappedValue = TextSelection(insertionPoint: new.index(new.startIndex, offsetBy: clamped))

        anchor = fixed ? at + ins.count : at
        live = (fixed || ins.isEmpty) ? "" : ins
        if fixed { adopted = 0 }                       // the window moved on
        lastValue = new

        let delta = ins.count - (end - at)
        for k in chips.indices where chips[k].at >= end { chips[k].at += delta }
        if fixed && !ins.isEmpty {
            for k in segments.indices where segments[k].at >= end { segments[k].at += delta }
            segments.append((at + lead.count, text))
            snapshot = new
            // `start` counts UTF-16 units of the text as the server sent it; `text` may start later if words were adopted.
            let skip = incoming.range(of: text, options: .backwards).map { incoming.distance(from: incoming.startIndex, to: $0.lowerBound) } ?? 0
            for sub in subs {
                let kind: DictationChip.Kind
                switch sub.state {
                case "applied": kind = .applied
                case "suggested": kind = .suggested
                default: continue
                }
                let units = incoming.utf16
                let index = units.index(units.startIndex, offsetBy: min(sub.start, units.count))
                let offset = incoming.distance(from: incoming.startIndex, to: index) - skip
                guard offset >= 0 else { continue }
                addChip(DictationChip(kind: kind, serverId: sub.id, heard: sub.heard, intended: sub.intended, at: at + lead.count + offset))
            }
        }
    }

    // MARK: chips

    private func addChip(_ chip: DictationChip) {
        chips.removeAll { $0.kind == chip.kind && $0.heard == chip.heard && $0.intended == chip.intended }
        chips.append(chip)
        if chips.count > 6 { chips.removeFirst() }
    }

    /// An edit replaced [editStart, editEnd) with text `delta` longer. Chips after it move; a chip whose word was
    /// edited is the author's now and goes away.
    private func shiftChips(editStart: Int, editEnd: Int, delta: Int) {
        chips = chips.compactMap { chip in
            guard chip.at >= 0 else { return chip }
            let length = (chip.kind == .applied ? chip.intended : chip.heard).count
            var c = chip
            if editEnd <= chip.at { c.at += delta }
            else if editStart < chip.at + length { return nil }
            return c
        }
    }

    func act(on chip: DictationChip) {
        chips.removeAll { $0.id == chip.id }
        switch chip.kind {
        case .applied:
            swapText(at: chip.at, old: chip.intended, new: chip.heard)
            if let id = chip.serverId {
                client?.fire("POST", "/api/dictation/corrections/\(id)/undo")
            } else if let body = try? JSONEncoder().encode(KeepRequest(bookId: bookId, heard: chip.heard)) {
                client?.fire("POST", "/api/dictation/corrections/keep", body: body)    // a Codex snap: leave this word alone from now on
            }
        case .suggested:
            swapText(at: chip.at, old: chip.heard, new: chip.intended)
            if let body = try? JSONEncoder().encode(LearnRequest(bookId: bookId, edits: [LearnEdit(heard: chip.heard, intended: chip.intended)])) {
                client?.fire("POST", "/api/dictation/corrections/learn", body: body)
            }
        case .learned:
            if chip.created, let id = chip.serverId { client?.fire("DELETE", "/api/dictation/corrections/\(id)") }
        }
    }

    /// Replaces text in the field and in the snapshot together, so an undo is never mistaken for the author's fix.
    private func swapText(at: Int, old: String, new: String) {
        guard let f = learnField else { return }
        var chars = Array(f.text.wrappedValue)
        let o = Array(old), n = Array(new)
        var i = -1
        if at >= 0, at + o.count <= chars.count, Array(chars[at..<(at + o.count)]) == o { i = at }
        else if !o.isEmpty, chars.count >= o.count {
            for k in 0...(chars.count - o.count) where Array(chars[k..<(k + o.count)]) == o {
                if i < 0 || abs(k - at) < abs(i - at) { i = k }
            }
        }
        guard i >= 0 else { return }
        let delta = n.count - o.count
        let caret = caretOffset(in: f.text.wrappedValue)
        chars.replaceSubrange(i..<(i + o.count), with: n)
        let text = String(chars)

        var sc = Array(snapshot)
        if i + o.count <= sc.count, Array(sc[i..<(i + o.count)]) == o { sc.replaceSubrange(i..<(i + o.count), with: n); snapshot = String(sc) }
        for k in segments.indices where segments[k].at > i { segments[k].at += delta }
        for k in chips.indices where chips[k].at > i { chips[k].at += delta }
        if i + o.count <= anchor { anchor += delta }
        lastValue = text                                  // set first, so the field's change is not read as an edit
        f.text.wrappedValue = text
        if let caret {
            let c = max(0, min(caret <= i ? caret : caret + delta, chars.count))
            f.selection.wrappedValue = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: c))
        }
    }

    // MARK: learning from the author's edits

    private struct Word { let w: String; let s: Int; let e: Int }
    private struct Hunk { let old: String; let neu: String; let oldStart: Int; let oldEnd: Int; let n: Int; let m: Int }

    private static func words(_ chars: ArraySlice<Character>) -> [Word] {
        var out: [Word] = [], i = chars.startIndex
        while i < chars.endIndex {
            while i < chars.endIndex, chars[i].isWhitespace { i += 1 }
            let start = i
            while i < chars.endIndex, !chars[i].isWhitespace { i += 1 }
            if i > start { out.append(Word(w: String(chars[start..<i]), s: start - chars.startIndex, e: i - chars.startIndex)) }
        }
        return out
    }

    /// Word-level replacements between two texts (the desktop page's `hunks`).
    private static func hunks(_ a: [Character], _ b: [Character]) -> [Hunk] {
        var p = 0
        while p < min(a.count, b.count), a[p] == b[p] { p += 1 }
        while p > 0, !a[p - 1].isWhitespace { p -= 1 }
        var sa = a.count, sb = b.count
        while sa > p, sb > p, a[sa - 1] == b[sb - 1] { sa -= 1; sb -= 1 }
        while sa < a.count, !a[sa].isWhitespace { sa += 1; sb = min(sb + 1, b.count) }
        let A = words(a[p..<sa]), B = words(b[p..<max(sb, p)])
        if A.count > 300 || B.count > 300 { return [] }
        var L = Array(repeating: Array(repeating: 0, count: B.count + 1), count: A.count + 1)
        if !A.isEmpty && !B.isEmpty {
            for i in stride(from: A.count - 1, through: 0, by: -1) {
                for j in stride(from: B.count - 1, through: 0, by: -1) {
                    L[i][j] = A[i].w == B[j].w ? L[i + 1][j + 1] + 1 : max(L[i + 1][j], L[i][j + 1])
                }
            }
        }
        var out: [Hunk] = []
        var i = 0, j = 0, i0 = -1, j0 = -1
        func flush() {
            if i0 >= 0, i > i0, j > j0 {
                out.append(Hunk(old: String(a[(p + A[i0].s)..<(p + A[i - 1].e)]), neu: String(b[(p + B[j0].s)..<(p + B[j - 1].e)]),
                                oldStart: p + A[i0].s, oldEnd: p + A[i - 1].e, n: i - i0, m: j - j0))
            }
            i0 = -1; j0 = -1
        }
        while i < A.count || j < B.count {
            if i < A.count, j < B.count, A[i].w == B[j].w { flush(); i += 1; j += 1; continue }
            if i0 < 0 { i0 = i; j0 = j }
            if j >= B.count || (i < A.count && L[i + 1][j] >= L[i][j + 1]) { i += 1 } else { j += 1 }
        }
        flush()
        return out
    }

    /// Reports the author's own word fixes inside dictated text, so the server can learn them. Runs when edits have
    /// been quiet for four seconds, before the next dictated segment lands, on send and when the chat leaves the screen.
    func settle() {
        settleTask?.cancel(); settleTask = nil
        guard let f = learnField, dirty else { return }
        dirty = false
        var cur = Array(f.text.wrappedValue)
        let liveChars = Array(live)
        if field != nil, !liveChars.isEmpty, anchor + liveChars.count <= cur.count, Array(cur[anchor..<(anchor + liveChars.count)]) == liveChars {
            cur.removeSubrange(anchor..<(anchor + liveChars.count))
        }
        let current = String(cur)
        if current == snapshot { return }
        let hs = Self.hunks(Array(snapshot), cur).filter { $0.n <= 4 && $0.m <= 4 }
        func segment(_ h: Hunk) -> Int? { segments.firstIndex { h.oldStart < $0.at + $0.text.count && h.oldEnd > $0.at } }
        var changed: [Int: Int] = [:]
        for h in hs { if let k = segment(h) { changed[k, default: 0] += h.n } }
        var edits: [LearnEdit] = []
        for h in hs {
            guard let k = segment(h) else { continue }
            let size = segments[k].text.split(whereSeparator: \.isWhitespace).count
            if changed[k, default: 0] > max(1, size / 2) { continue }      // rewriting most of a passage is writing
            let trim = CharacterSet.alphanumerics.inverted
            let heard = h.old.trimmingCharacters(in: trim), intended = h.neu.trimmingCharacters(in: trim)
            let hw = heard.lowercased().split(whereSeparator: \.isWhitespace), iw = intended.lowercased().split(whereSeparator: \.isWhitespace)
            if hw.allSatisfy({ iw.contains($0) }) || iw.allSatisfy({ hw.contains($0) }) { continue }   // a word added or dropped
            if !heard.isEmpty && !intended.isEmpty { edits.append(LearnEdit(heard: heard, intended: intended)) }
        }
        segments = segments.compactMap { g in
            guard let r = current.range(of: g.text) else { return nil }
            return (current.distance(from: current.startIndex, to: r.lowerBound), g.text)
        }
        snapshot = current
        guard !edits.isEmpty, let client else { return }
        let request = LearnRequest(bookId: bookId, edits: edits)
        Task { [weak self] in
            guard let reply: LearnReply = try? await client.post("/api/dictation/corrections/learn", body: request) else { return }
            for l in reply.learned {
                self?.addChip(DictationChip(kind: .learned, serverId: l.id, heard: l.heard, intended: l.intended, at: -1, created: l.created))
            }
        }
    }
}
