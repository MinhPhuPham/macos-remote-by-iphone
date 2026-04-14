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
                Label("permissions_required", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                if !hasScreenRecording {
                    permissionItem(
                        title: "screen_recording_title",
                        description: "screen_recording_required_desc",
                        action: onRequestScreenRecording
                    )
                }

                if !hasAccessibility {
                    permissionItem(
                        title: "accessibility_title",
                        description: "accessibility_required_desc",
                        action: onRequestAccessibility
                    )
                }

                Text("grant_permissions_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func permissionItem(title: LocalizedStringKey, description: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("grant_button") { action() }
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
            Label("connection_request", systemImage: "person.badge.shield.checkmark")
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

            Text("connection_warning")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("allow_once", action: onApproveOnce)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("always_allow", action: onApproveAlways)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button("deny", role: .destructive, action: onDeny)
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
                    .tabItem { Label("tab_general", systemImage: "gear") }
                    .tag("general")

                securityTab
                    .tabItem { Label("tab_security", systemImage: "lock.shield") }
                    .tag("security")

                devicesTab
                    .tabItem { Label("tab_devices", systemImage: "iphone") }
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
            Section("section_server") {
                if isEditingName {
                    HStack {
                        TextField("server_name_placeholder", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveName() }

                        Button("save_button") { saveName() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("cancel_button") { isEditingName = false }
                            .controlSize(.small)
                    }
                } else {
                    LabeledContent("label_name") {
                        HStack(spacing: 8) {
                            Text(server.serverName)
                            Button("edit_button") {
                                editingName = server.serverName
                                isEditingName = true
                            }
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("label_port") {
                    Text("\(MyRemoteConstants.defaultPort)")
                        .foregroundStyle(.secondary)
                }

                Picker("stream_quality", selection: $server.streamQuality) {
                    ForEach(ServerManager.StreamQuality.allCases) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }

                LabeledContent("label_status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(server.isRunning ? LocalizedStringKey("status_running") : LocalizedStringKey("status_stopped"))
                    }
                }
            }

            Section("section_permissions") {
                permissionRow(
                    title: "screen_recording_title",
                    description: "screen_recording_desc",
                    isGranted: hasScreenRecording
                ) {
                    ScreenCaptureManager.requestPermission()
                    refreshPermissions()
                }

                permissionRow(
                    title: "accessibility_title",
                    description: "accessibility_desc",
                    isGranted: hasAccessibility
                ) {
                    MouseInjector.requestAccessibilityPermission()
                    refreshPermissions()
                }

                Button("open_system_settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
                .font(.caption)
            }

            Section("section_network") {
                LabeledContent("label_local_ip") {
                    Text("\(server.localIP):\(MyRemoteConstants.defaultPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("label_public_ip") {
                    Text("\(server.publicIP):\(MyRemoteConstants.defaultPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                DisclosureGroup("remote_access_guide") {
                    VStack(alignment: .leading, spacing: 8) {
                        guideStep(1, String(localized: "guide_step_1"))
                        guideStep(2, String(localized: "guide_step_2"))
                        guideStep(3, String(localized: "guide_step_3 \(server.localIP)"))
                        guideStep(4, String(localized: "guide_step_4 \(server.publicIP)"))
                        guideStep(5, String(localized: "guide_step_5"))

                        Divider()

                        Text("guide_vpn_note")
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
            Section("section_current_pin") {
                HStack {
                    if showPassword {
                        Text(currentPIN)
                            .font(.title2.monospaced())
                    } else {
                        Text(String(repeating: "\u{2022}", count: currentPIN.count))
                            .font(.title2)
                    }
                    Spacer()
                    Button(showPassword ? LocalizedStringKey("hide_button") : LocalizedStringKey("show_button")) {
                        showPassword.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Button("generate_new_pin") {
                    do {
                        let pin = try server.authManager.generatePIN()
                        currentPIN = pin
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            Section("section_custom_password") {
                SecureField("password_placeholder", text: $passwordInput)

                Button("set_password") {
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
            Section("section_trusted_devices") {
                if server.trustedDeviceStore.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("no_trusted_devices")
                            .foregroundStyle(.secondary)
                        Text("trusted_devices_hint")
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
                                Text("trusted_date \(device.dateAdded.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button("revoke_button", role: .destructive) {
                                deviceToRevoke = device
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if !server.trustedDeviceStore.devices.isEmpty {
                    Button("revoke_all_devices", role: .destructive) {
                        server.trustedDeviceStore.revokeAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "revoke_confirm_title \(deviceToRevoke?.name ?? "")",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("revoke_button", role: .destructive) {
                if let device = deviceToRevoke {
                    server.trustedDeviceStore.revoke(deviceUUID: device.id)
                }
                deviceToRevoke = nil
            }
            Button("cancel_button", role: .cancel) {
                deviceToRevoke = nil
            }
        } message: {
            Text("revoke_confirm_message")
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
        title: LocalizedStringKey,
        description: LocalizedStringKey,
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
                Label("permission_granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("grant_button") { action() }
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
