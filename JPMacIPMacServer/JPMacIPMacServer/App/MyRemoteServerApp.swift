import SwiftUI

/// macOS server app — runs as a menu bar extra (no dock icon).
@main
struct MyRemoteServerApp: App {

    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra("MyRemote", systemImage: server.statusIcon) {
            MenuBarView(server: server)
        }

        Settings {
            SettingsView(server: server)
        }
    }
}
