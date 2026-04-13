import SwiftUI

/// Content for the menu bar extra dropdown.
struct MenuBarView: View {

    @ObservedObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pending = server.pendingApproval {
                approvalSection(pending)
                Divider()
            }

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

    // MARK: - Approval

    private func approvalSection(_ pending: ServerManager.PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark")
                    .foregroundStyle(.orange)
                Text("Connection Request")
                    .font(.subheadline.bold())
            }

            Text("\"\(pending.deviceName)\" (\(pending.clientIP)) wants to connect.")
                .font(.caption)

            Text("This device will see your screen and control mouse & keyboard.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Allow Once") {
                    server.approveConnection(trustPermanently: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Always Allow") {
                    server.approveConnection(trustPermanently: true)
                }
                .controlSize(.small)

                Button("Deny") {
                    server.denyConnection()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(server.statusMessage)
                    .font(.subheadline)
            }

            if let clientName = server.authManager.connectedDeviceName {
                Text("Client: \(clientName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if server.isRunning && server.connectedClient == nil {
                Divider().padding(.vertical, 2)
                HStack(spacing: 4) {
                    Image(systemName: "link.circle")
                        .foregroundStyle(.blue)
                    Text("Pairing Code:")
                        .font(.caption)
                    Text(server.pairingManager.formattedCode)
                        .font(.system(.caption, design: .monospaced).bold())
                        .textSelection(.enabled)
                }

                if !server.pairingManager.isRegistered {
                    Text("Signaling server offline — use Manual IP")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server status: \(server.statusMessage)")
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

            Divider()

            Button("Open Setup Guide...") {
                openWindow(id: "onboarding")
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
