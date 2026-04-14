import SwiftUI

/// Onboarding view — shown on first launch to guide the user through
/// permission setup and auto-start the server.
struct OnboardingView: View {

    @ObservedObject var server: ServerManager
    var onComplete: (() -> Void)?
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
            refreshPermissions()
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("welcome_title")
                .font(.largeTitle.bold())

            Text("welcome_subtitle")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("get_started") {
                withAnimation { step = .permissions }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Permissions Step

    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Text("required_permissions")
                .font(.title.bold())

            VStack(spacing: 16) {
                permissionRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "screen_recording_title",
                    description: "screen_recording_needed_desc",
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
                    title: "accessibility_title",
                    description: "accessibility_needed_desc",
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
                Button("refresh_status") {
                    refreshPermissions()
                }
                .buttonStyle(.bordered)

                Button("continue_button") {
                    withAnimation { step = .ready }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("permissions_change_hint")
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

            Text("all_set_title")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: String(localized: "instruction_step_1"))
                instructionRow(number: "2", text: String(localized: "instruction_step_2"))
                instructionRow(number: "3", text: String(localized: "instruction_step_3"))
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))

            if let pin = server.authManager.currentPassword() {
                VStack(spacing: 4) {
                    Text("your_pin_label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(.title, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
            }

            Button("start_server_and_close") {
                if !server.isRunning {
                    server.start()
                }
                onComplete?()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func permissionRow(
        icon: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
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
                Label("permission_granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("grant_button") { action() }
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
