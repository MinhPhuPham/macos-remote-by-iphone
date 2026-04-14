import SwiftUI

/// Notification posted when onboarding should open.
extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
}

/// macOS server app — runs as a menu bar extra (no dock icon).
@main
struct MyRemoteServerApp: App {

    @StateObject private var server = ServerManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra("MyRemote", systemImage: server.statusIcon) {
            MenuBarView(server: server)
                .frame(width: 280)
                // onReceive fires even in hidden MenuBarExtra (view is in hierarchy).
                .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                    openWindow(id: "onboarding")
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(server: server)
                .onAppear { bringAppToFront() }
                .onDisappear { hideAppIfNoWindows() }
        }

        Window("MyRemote Setup", id: "onboarding") {
            OnboardingView(server: server) {
                hasCompletedOnboarding = true
            }
            .onAppear { bringAppToFront() }
            .onDisappear { hideAppIfNoWindows() }
        }
        .defaultSize(width: 500, height: 420)
    }

    @Environment(\.openWindow) private var openWindow

    init() {
        // Schedule onboarding check — can't use openWindow in init (no environment yet).
        // A notification triggers the MenuBarView's onReceive which HAS the environment.
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }
        }
    }

    /// Bring the app to the foreground so Settings/Onboarding windows are visible.
    /// For LSUIElement apps, NSApp.activate() alone doesn't force windows to front.
    /// We must also explicitly order the window front.
    private func bringAppToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Find the topmost non-MenuBarExtra window and force it to front.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible && !window.title.isEmpty {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                break
            }
        }
    }

    /// Only hide from dock if no windows are still open.
    private func hideAppIfNoWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let hasVisibleWindows = NSApp.windows.contains {
                $0.isVisible && !$0.title.isEmpty
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
