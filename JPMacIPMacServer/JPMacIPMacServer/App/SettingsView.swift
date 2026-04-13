import JPMacIPRemoteShared
import SwiftUI

/// macOS Settings window: password management, trusted devices, stream quality, preferences.
struct SettingsView: View {

    @ObservedObject var server: ServerManager

    @State private var passwordInput = ""
    @State private var showPassword = false
    @State private var currentPIN: String = ""
    @State private var selectedTab = "general"
    @State private var errorMessage: String?

    var body: some View {
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
        .frame(width: 480, height: 360)
        .onAppear {
            // LSUIElement apps don't auto-activate — bring Settings window to front.
            NSApplication.shared.activate()
            currentPIN = server.authManager.currentPassword() ?? ""
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Server") {
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
                            .accessibilityHidden(true)
                        Text(server.isRunning ? "Running" : "Stopped")
                    }
                }
                .accessibilityLabel("Server status: \(server.isRunning ? "running" : "stopped")")
            }

            Section("Permissions") {
                HStack {
                    Text("Screen Recording")
                    Spacer()
                    if ScreenCaptureManager.hasPermission() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Request") {
                            ScreenCaptureManager.requestPermission()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Screen Recording permission: \(ScreenCaptureManager.hasPermission() ? "granted" : "not granted")")

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if MouseInjector.hasAccessibilityPermission() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Request") {
                            MouseInjector.requestAccessibilityPermission()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Accessibility permission: \(MouseInjector.hasAccessibilityPermission() ? "granted" : "not granted")")
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

    private var devicesTab: some View {
        Form {
            Section("Trusted Devices") {
                if server.trustedDeviceStore.devices.isEmpty {
                    Text("No trusted devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.trustedDeviceStore.devices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.headline)
                                Text("Added \(device.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Revoke", role: .destructive) {
                                server.trustedDeviceStore.revoke(deviceUUID: device.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !server.trustedDeviceStore.devices.isEmpty {
                    Button("Revoke All", role: .destructive) {
                        server.trustedDeviceStore.revokeAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
