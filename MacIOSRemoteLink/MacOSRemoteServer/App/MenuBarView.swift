import SwiftUI

/// Content for the menu bar extra popover (`.window` style).
struct MenuBarView: View {

    @ObservedObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
        ApprovalBanner(
            pending: pending,
            onApproveOnce: { server.approveConnection(trustPermanently: false) },
            onApproveAlways: { server.approveConnection(trustPermanently: true) },
            onDeny: { server.denyConnection() }
        )
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

                VStack(alignment: .leading, spacing: 4) {
                    ipRow(label: "ip_label_local", value: "\(server.localIP):\(MyRemoteConstants.defaultPort)",
                          icon: "wifi", color: .blue)
                    ipRow(label: "ip_label_public", value: "\(server.publicIP):\(MyRemoteConstants.defaultPort)",
                          icon: "globe", color: .orange)
                }

                Text("remote_access_note")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if server.isRunning {
                menuButton("stop_server", icon: "stop.fill", role: .destructive) {
                    server.stop()
                }

                if server.connectedClient != nil {
                    menuButton("disconnect_client", icon: "xmark.circle") {
                        server.connectedClient?.disconnect()
                    }
                }
            } else {
                menuButton("start_server", icon: "play.fill") {
                    server.start()
                }
            }

            Divider().padding(.vertical, 2)

            // Only show Setup Guide if permissions are missing.
            if !ScreenCaptureManager.hasPermission() || !MouseInjector.hasAccessibilityPermission() {
                menuButton("setup_guide", icon: "questionmark.circle") {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "onboarding")
                    DispatchQueue.main.async {
                        NSApp.activate()
                        for window in NSApp.windows where window.isVisible && !window.title.isEmpty {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
            }

            menuButton("settings_menu", icon: "gear") {
                // openSettings() opens or brings the Settings window to front.
                // But for LSUIElement apps it stays behind — force it.
                NSApp.setActivationPolicy(.regular)
                openSettings()
                DispatchQueue.main.async {
                    NSApp.activate()
                    for window in NSApp.windows where window.isVisible && !window.title.isEmpty {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
            .keyboardShortcut(",")
        }
    }

    // MARK: - Quit

    private var quitButton: some View {
        menuButton("quit_app", icon: "power") {
            server.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private func menuButton(_ title: LocalizedStringKey, icon: String,
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

    private func ipRow(label: LocalizedStringKey, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var statusColor: Color {
        if server.connectedClient != nil { return .green }
        if server.isRunning { return .yellow }
        return .gray
    }
}
