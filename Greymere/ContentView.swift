import SwiftUI

struct ContentView: View {
    private var serverURL: String {
        Bundle.main.object(forInfoDictionaryKey: "GreymereDefaultServerURL") as? String ?? "not set"
    }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Greymere").font(.largeTitle)
            Text("iOS \(version)").foregroundStyle(.secondary)
            Text(serverURL).font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding()
    }
}
