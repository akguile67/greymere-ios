import SwiftUI

struct RootView: View {
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        ZStack {
            connection.theme.background.ignoresSafeArea()
            switch connection.state {
            case .connecting: ConnectingView()
            case .unreachable: CantConnectView()
            case .tooOld(let version): TooOldView(serverVersion: version)
            case .ready:
                if let client = connection.client {
                    HomeScreen(client: client)
                }
            }
        }
        .preferredColorScheme(connection.theme.scheme)
        .task { await connection.connect() }
    }
}
