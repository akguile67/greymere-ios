import SwiftUI

/// Shown only when the app cannot reach the server on its own, and the one place the address is changed.
struct CantConnectView: View {
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        @Bindable var connection = connection
        MessageScreen(title: "Can't reach the server",
                      message: "Check that Tailscale is on and the address is right.") {
            TextField("Server address", text: $connection.address)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 12))
            Button("Try again") { Task { await connection.connect() } }
                .buttonStyle(.glassProminent)
        }
    }
}

/// A safety net: only seen if the server is older than this app needs.
struct TooOldView: View {
    let serverVersion: String
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        MessageScreen(title: "The server is too old",
                      message: "This app needs server \(ConnectionModel.minimumServerVersion) or newer. This server is \(serverVersion). Update the server, then try again.") {
            Button("Try again") { Task { await connection.connect() } }
                .buttonStyle(.glassProminent)
        }
    }
}

struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Greymere").font(.serif(34))
            ProgressView()
        }
    }
}

private struct MessageScreen<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 14) {
            Text("Greymere").font(.serif(34))
            Text(title).font(.headline)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: 420)
        .padding(28)
    }
}
