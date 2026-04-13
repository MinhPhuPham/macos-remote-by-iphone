import SwiftUI

/// Content for the menu bar extra popover (`.window` style).
struct MenuBarView: View {

    @ObservedObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pending = server.pendingApproval {
                approvalSection(pending)
                divider
            }

            statusSection
            divider
            controlsSection
            divider
            quitButton
        }
        .padding(.vertical, 4)
    }

    private var divider: some View {
        Divider().padding(.vertical, 2)
    }

    // MARK: - Approval Request

    private func approvalSection(_ pending: ServerManager.PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connection Request", systemImage: "person.badge.shield.checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.deviceName)
                    .font(.headline)
                Text(pending.clientIP)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("This device will see your screen and control mouse & keyboard.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Allow Once") {
                    server.approveConnection(trustPermanently: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)

                Button("Always Allow") {
                    server.approveConnection(trustPermanently: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Deny") {
                    server.denyConnection()
                }
                .foregroundStyle(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(server.statusMessage)
                    .font(.subheadline)
            }

            if let clientName = server.authManager.connectedDeviceName {
                Label(clientName, systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if server.isRunning && server.connectedClient == nil {
                Divider().padding(.vertical, 2)
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .foregroundStyle(.blue)
                    Text("Port:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(MyRemoteConstants.defaultPort)")
                        .font(.system(.body, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if server.isRunning {
                menuButton("Stop Server", icon: "stop.fill", role: .destructive) {
                    server.stop()
                }

                if server.connectedClient != nil {
                    menuButton("Disconnect Client", icon: "xmark.circle") {
                        server.connectedClient?.disconnect()
                    }
                }
            } else {
                menuButton("Start Server", icon: "play.fill") {
                    server.start()
                }
            }

            Divider().padding(.vertical, 2)

            menuButton("Setup Guide...", icon: "questionmark.circle") {
                openWindow(id: "onboarding")
            }

            SettingsLink {
                Label("Settings...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .keyboardShortcut(",")
        }
    }

    // MARK: - Quit

    private var quitButton: some View {
        menuButton("Quit MyRemote", icon: "power") {
            server.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private func menuButton(_ title: String, icon: String,
                            role: ButtonRole? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if server.connectedClient != nil { return .green }
        if server.isRunning { return .yellow }
        return .gray
    }
}
