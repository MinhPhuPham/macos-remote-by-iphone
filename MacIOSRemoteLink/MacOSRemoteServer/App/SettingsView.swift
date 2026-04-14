import SwiftUI

// MARK: - Reusable Permission Banner

/// A warning banner that shows when required permissions are not granted.
/// Reusable across Settings, Onboarding, or any view that needs it.
struct PermissionBanner: View {

    let hasScreenRecording: Bool
    let hasAccessibility: Bool
    let onRequestScreenRecording: () -> Void
    let onRequestAccessibility: () -> Void

    var allGranted: Bool { hasScreenRecording && hasAccessibility }

    var body: some View {
        if !allGranted {
            VStack(alignment: .leading, spacing: 8) {
                Label("Permissions Required", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                if !hasScreenRecording {
                    permissionItem(
                        title: "Screen Recording",
                        description: "Required to capture and stream your screen",
                        action: onRequestScreenRecording
                    )
                }

                if !hasAccessibility {
                    permissionItem(
                        title: "Accessibility",
                        description: "Required to control mouse and keyboard",
                        action: onRequestAccessibility
                    )
                }

                Text("Grant permissions in System Settings → Privacy & Security")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func permissionItem(title: String, description: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant") { action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Approval Banner (reusable)

/// Shows a pending connection request. Reusable in MenuBarView and SettingsView.
struct ApprovalBanner: View {

    let pending: ServerManager.PendingApproval
    let onApproveOnce: () -> Void
    let onApproveAlways: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection Request", systemImage: "person.badge.shield.checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)

            HStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.deviceName).font(.headline)
                    Text(pending.deviceModel)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(pending.clientIP)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Text("This device will see your screen and control mouse & keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Allow Once", action: onApproveOnce)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Always Allow", action: onApproveAlways)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button("Deny", role: .destructive, action: onDeny)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Settings View

/// macOS Settings window: password management, trusted devices, stream quality, permissions.
struct SettingsView: View {

    @ObservedObject var server: ServerManager

    @State private var passwordInput = ""
    @State private var showPassword = false
    @State private var currentPIN: String = ""
    @State private var selectedTab = "general"
    @State private var errorMessage: String?
    @State private var hasScreenRecording = ScreenCaptureManager.hasPermission()
    @State private var hasAccessibility = MouseInjector.hasAccessibilityPermission()
    @State private var isEditingName = false
    @State private var editingName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Permission banner at top — always visible when permissions missing.
            PermissionBanner(
                hasScreenRecording: hasScreenRecording,
                hasAccessibility: hasAccessibility,
                onRequestScreenRecording: {
                    ScreenCaptureManager.requestPermission()
                    refreshPermissions()
                },
                onRequestAccessibility: {
                    MouseInjector.requestAccessibilityPermission()
                    refreshPermissions()
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Approval banner — visible when a device is waiting.
            if let pending = server.pendingApproval {
                ApprovalBanner(
                    pending: pending,
                    onApproveOnce: { server.approveConnection(trustPermanently: false) },
                    onApproveAlways: { server.approveConnection(trustPermanently: true) },
                    onDeny: { server.denyConnection() }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("General", systemImage: "gear") }
                    .tag("general")

                securityTab
                    .tabItem { Label("Security", systemImage: "lock.shield") }
                    .tag("security")

                devicesTab
                    .tabItem { Label("Devices", systemImage: "iphone") }
                    .tag("devices")
            }
        }
        .frame(width: 500, height: 440)
        .onAppear {
            currentPIN = server.authManager.currentPassword() ?? ""
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        // Delay slightly for system to update after granting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hasScreenRecording = ScreenCaptureManager.hasPermission()
            hasAccessibility = MouseInjector.hasAccessibilityPermission()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Server") {
                if isEditingName {
                    HStack {
                        TextField("Server Name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveName() }

                        Button("Save") { saveName() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") { isEditingName = false }
                            .controlSize(.small)
                    }
                } else {
                    LabeledContent("Name") {
                        HStack(spacing: 8) {
                            Text(server.serverName)
                            Button("Edit") {
                                editingName = server.serverName
                                isEditingName = true
                            }
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("Port") {
                    Text("\(MyRemoteConstants.defaultPort)")
                        .foregroundStyle(.secondary)
                }

                Picker("Stream Quality", selection: $server.streamQuality) {
                    ForEach(ServerManager.StreamQuality.allCases) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(server.isRunning ? "Running" : "Stopped")
                    }
                }
            }

            Section("Permissions") {
                permissionRow(
                    title: "Screen Recording",
                    description: "Capture and stream your screen",
                    isGranted: hasScreenRecording
                ) {
                    ScreenCaptureManager.requestPermission()
                    refreshPermissions()
                }

                permissionRow(
                    title: "Accessibility",
                    description: "Control mouse and keyboard",
                    isGranted: hasAccessibility
                ) {
                    MouseInjector.requestAccessibilityPermission()
                    refreshPermissions()
                }

                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
                .font(.caption)
            }

            Section("Network") {
                LabeledContent("Local IP") {
                    Text("\(server.localIP):\(MyRemoteConstants.defaultPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Public IP") {
                    Text("\(server.publicIP):\(MyRemoteConstants.defaultPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                DisclosureGroup("Remote Access Setup Guide") {
                    VStack(alignment: .leading, spacing: 8) {
                        guideStep(1, "Open your router admin page (usually 192.168.1.1)")
                        guideStep(2, "Find 'Port Forwarding' or 'Virtual Server' or 'NAT'")
                        guideStep(3, "Add rule: External port 5910 → \(server.localIP):5910 TCP")
                        guideStep(4, "On iPhone, enter your Public IP: \(server.publicIP)")
                        guideStep(5, "Make sure macOS Firewall allows incoming connections")

                        Divider()

                        Text("If you don't have router admin access, you'll need a VPN (e.g. Tailscale) or a relay server to connect remotely.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Security Tab

    private var securityTab: some View {
        Form {
            Section("Current PIN / Password") {
                HStack {
                    if showPassword {
                        Text(currentPIN)
                            .font(.title2.monospaced())
                    } else {
                        Text(String(repeating: "\u{2022}", count: currentPIN.count))
                            .font(.title2)
                    }
                    Spacer()
                    Button(showPassword ? "Hide" : "Show") {
                        showPassword.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Button("Generate New PIN") {
                    do {
                        let pin = try server.authManager.generatePIN()
                        currentPIN = pin
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            Section("Set Custom Password") {
                SecureField("New password (min 8 characters)", text: $passwordInput)

                Button("Set Password") {
                    guard passwordInput.count >= 8 else { return }
                    do {
                        try server.authManager.setPassword(passwordInput)
                        currentPIN = passwordInput
                        passwordInput = ""
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(passwordInput.count < 8)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Devices Tab

    @State private var deviceToRevoke: TrustedDevice?

    private var devicesTab: some View {
        Form {
            Section("Trusted Devices") {
                if server.trustedDeviceStore.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No trusted devices")
                            .foregroundStyle(.secondary)
                        Text("Devices approved with \"Always Allow\" appear here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(server.trustedDeviceStore.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: "iphone")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.headline)
                                Text(device.model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Trusted \(device.dateAdded.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button("Revoke", role: .destructive) {
                                deviceToRevoke = device
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if !server.trustedDeviceStore.devices.isEmpty {
                    Button("Revoke All Devices", role: .destructive) {
                        server.trustedDeviceStore.revokeAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Revoke \"\(deviceToRevoke?.name ?? "")\"?",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let device = deviceToRevoke {
                    server.trustedDeviceStore.revoke(deviceUUID: device.id)
                }
                deviceToRevoke = nil
            }
            Button("Cancel", role: .cancel) {
                deviceToRevoke = nil
            }
        } message: {
            Text("This device will need to be approved again on next connection.")
        }
    }

    // MARK: - Actions

    private func saveName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        server.serverName = trimmed
        isEditingName = false
    }

    // MARK: - Helpers

    private func permissionRow(
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))
            Text(text)
                .font(.callout)
        }
    }
}
