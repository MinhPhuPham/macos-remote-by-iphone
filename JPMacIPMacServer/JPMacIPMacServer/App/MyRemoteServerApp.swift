import SwiftUI

/// macOS server app — runs as a menu bar extra (no dock icon).
@main
struct MyRemoteServerApp: App {

    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra("MyRemote", systemImage: server.statusIcon) {
            MenuBarView(server: server)
                .frame(width: 280)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(server: server)
        }

        Window("MyRemote Setup", id: "onboarding") {
            OnboardingView(server: server)
        }
        .defaultSize(width: 500, height: 420)
    }
}
