import SwiftUI

/// iOS client app entry point.
@main
struct MyRemoteClientApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Connection and video pipeline are paused/cleaned up
                // by RemoteSessionView.onDisappear when backgrounded.
                break
            case .active:
                break
            default:
                break
            }
        }
    }
}
