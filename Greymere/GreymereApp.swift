import SwiftUI

@main
struct GreymereApp: App {
    @State private var connection = ConnectionModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(connection)
        }
    }
}
