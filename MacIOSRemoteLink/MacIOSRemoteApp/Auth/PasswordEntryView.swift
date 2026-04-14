import SwiftUI

/// Password entry screen shown after selecting a server.
struct PasswordEntryView: View {

    let serverName: String
    let onSubmit: (String) -> Void

    @State private var password = ""
    @State private var isSecure = true
    @FocusState private var isPasswordFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            serverHeader

            passwordField

            connectButton
        }
        .padding(32)
        .navigationTitle(Text("connect_title"))
        .onAppear {
            isPasswordFieldFocused = true
        }
    }

    // MARK: - Subviews

    private var serverHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(serverName)
                .font(.title2.bold())

            Text("enter_pin_hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var passwordField: some View {
        HStack {
            Group {
                if isSecure {
                    SecureField("pin_or_password_placeholder", text: $password)
                } else {
                    TextField("pin_or_password_placeholder", text: $password)
                }
            }
            .textContentType(.password)
            .focused($isPasswordFieldFocused)
            .submitLabel(.go)
            .onSubmit { submitIfValid() }

            Button {
                isSecure.toggle()
            } label: {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectButton: some View {
        Button(action: submitIfValid) {
            Text("connect_button")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(password.isEmpty)
        .accessibilityHint("Sends the password to the Mac for authentication")
    }

    private func submitIfValid() {
        guard !password.isEmpty else { return }
        onSubmit(password)
    }
}
