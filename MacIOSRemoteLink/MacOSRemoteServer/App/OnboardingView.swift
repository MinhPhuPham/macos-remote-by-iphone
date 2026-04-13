import SwiftUI

/// Onboarding view — shown on first launch to guide the user through
/// permission setup and auto-start the server.
struct OnboardingView: View {

    @ObservedObject var server: ServerManager
    @Environment(\.dismiss) private var dismiss

    @State private var hasScreenRecording = ScreenCaptureManager.hasPermission()
    @State private var hasAccessibility = MouseInjector.hasAccessibilityPermission()
    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep: CaseIterable {
        case welcome
        case permissions
        case ready
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:
                welcomeStep
            case .permissions:
                permissionsStep
            case .ready:
                readyStep
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            NSApplication.shared.activate()
            refreshPermissions()
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Welcome to MyRemote")
                .font(.largeTitle.bold())

            Text("Control your Mac from your iPhone.\nLet's set up the required permissions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Get Started") {
                withAnimation { step = .permissions }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Permissions Step

    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Text("Required Permissions")
                .font(.title.bold())

            VStack(spacing: 16) {
                permissionRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "Screen Recording",
                    description: "Needed to capture and stream your screen",
                    isGranted: hasScreenRecording
                ) {
                    ScreenCaptureManager.requestPermission()
                    // Refresh after a delay since the permission dialog is async.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        refreshPermissions()
                    }
                }

                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Needed to control mouse and keyboard",
                    isGranted: hasAccessibility
                ) {
                    MouseInjector.requestAccessibilityPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        refreshPermissions()
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))

            HStack(spacing: 16) {
                Button("Refresh Status") {
                    refreshPermissions()
                }
                .buttonStyle(.bordered)

                Button("Continue") {
                    withAnimation { step = .ready }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("You can change these later in\nSystem Settings → Privacy & Security")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Ready Step

    private var readyStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "The server is starting automatically")
                instructionRow(number: "2", text: "Look for the MyRemote icon in your menu bar")
                instructionRow(number: "3", text: "Open MyRemote on your iPhone to connect")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))

            if let pin = server.authManager.currentPassword() {
                VStack(spacing: 4) {
                    Text("Your PIN:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(.title, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
            }

            Button("Start Server & Close") {
                if !server.isRunning {
                    server.start()
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
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
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.callout)
        }
    }

    private func refreshPermissions() {
        hasScreenRecording = ScreenCaptureManager.hasPermission()
        hasAccessibility = MouseInjector.hasAccessibilityPermission()
    }
}
