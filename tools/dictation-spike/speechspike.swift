import Foundation
import Speech
import AVFoundation

// Throwaway: transcribe one file with Apple's on-device SpeechTranscriber, plain or with contextual strings.
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: speechspike <audio> <plain|context|status>"); exit(2) }
let url = URL(fileURLWithPath: args[1])
let mode = args[2]

let names = ["Leah Tran", "DCI Arthur Calder", "Besnik Bajraktari", "Dritan Hysaj", "Sokol Bajraktari", "Luan Bajraktari",
             "Lindita Hysaj", "Sofia Hysaj", "Fatos", "Erion", "Klea", "Marjeta", "Mia Florescu", "Ana Florescu", "Marta Florea",
             "Dara Voss", "Alderton Bay", "Sunset View", "Văleni", "Iza Valley", "Maramureș", "Sarandë", "Tirana", "Durrës",
             "Shkodër", "The Greymere Chronicle"]

func runCustom() async throws {
    // The proper custom vocabulary: a custom language model of the names, used with DictationTranscriber.
    let locale = Locale(identifier: "en_GB")
    let data = SFCustomLanguageModelData(locale: locale, identifier: "com.greymere.spike", version: "1.0") {
        for n in names { SFCustomLanguageModelData.PhraseCount(phrase: n, count: 200) }
        SFCustomLanguageModelData.PhraseCount(phrase: "Fatos and Erion", count: 200)
        SFCustomLanguageModelData.PhraseCount(phrase: "Dritan Hysaj and Sokol Bajraktari", count: 100)
        SFCustomLanguageModelData.PhraseCount(phrase: "Lindita Hysaj and Sofia Hysaj", count: 100)
    }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spike-lm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dataURL = dir.appendingPathComponent("names.bin")
    try await data.export(to: dataURL)
    let modelURL = dir.appendingPathComponent("names.lm")
    let config = SFSpeechLanguageModel.Configuration(languageModel: modelURL)
    try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: dataURL, configuration: config)
    print("custom language model prepared")
    let transcriber = DictationTranscriber(locale: locale, contentHints: [.customizedLanguage(modelConfiguration: config)],
                                           transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [])
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    var text = ""
    let collector = Task { for try await r in transcriber.results { text += String(r.text.characters) + " " } }
    let file = try AVAudioFile(forReading: url)
    let t0 = Date()
    if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
    else { await analyzer.cancelAndFinishNow() }
    try await collector.value
    FileHandle.standardError.write(Data("took \(Date().timeIntervalSince(t0))s\n".utf8))
    print(text)
}

func run() async throws {
    if mode == "custom" { try await runCustom(); return }
    let locale = Locale(identifier: "en-GB")
    guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { print("locale not supported"); return }
    let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
    let status = await AssetInventory.status(forModules: [transcriber])
    print("locale \(supported.identifier); model status: \(status)")
    if mode == "status" { return }
    let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier == supported.identifier }
    guard status == .installed || installed else { print("MODEL NOT INSTALLED: not downloading without permission"); return }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    if mode == "context" {
        let ctx = AnalysisContext()
        ctx.contextualStrings[.general] = names
        try await analyzer.setContext(ctx)
    }
    var text = ""
    let collector = Task {
        for try await r in transcriber.results { text += String(r.text.characters) + " " }
    }
    let file = try AVAudioFile(forReading: url)
    let t0 = Date()
    if let last = try await analyzer.analyzeSequence(from: file) {
        try await analyzer.finalizeAndFinish(through: last)
    } else {
        await analyzer.cancelAndFinishNow()
    }
    try await collector.value
    FileHandle.standardError.write(Data("took \(Date().timeIntervalSince(t0))s\n".utf8))
    print(text)
}

Task { do { try await run() } catch { print("ERROR: \(error)") }; exit(0) }
RunLoop.main.run()
