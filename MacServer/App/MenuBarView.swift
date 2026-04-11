import SwiftUI

/// Content for the menu bar extra dropdown.
struct MenuBarView: View {

    @ObservedObject var server: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection

            Divider()

            controlsSection

            Divider()

            Button("Quit MyRemote") {
                server.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(server.statusMessage)
                    .font(.subheadline)
            }

            if let clientName = server.authManager.connectedDeviceName {
                Text("Client: \(clientName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var controlsSection: some View {
        Group {
            if server.isRunning {
                Button("Stop Server") {
                    server.stop()
                }

                if server.connectedClient != nil {
                    Button("Disconnect Client") {
                        server.connectedClient?.disconnect()
                    }
                }
            } else {
                Button("Start Server") {
                    server.start()
                }
            }

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")
        }
    }

    private var statusColor: Color {
        if server.connectedClient != nil { return .green }
        if server.isRunning { return .yellow }
        return .gray
    }
}
