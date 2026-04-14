import SwiftUI

/// Manual connection view for WAN/cellular — enter hostname/IP and port.
struct ManualConnectionView: View {

    let onConnect: (String, UInt16) -> Void

    @State private var host = ""
    @State private var portString = "\(MyRemoteConstants.defaultPort)"
    @FocusState private var focusedField: Field?

    private enum Field {
        case host, port
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                inputFields
                connectButton
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        // Auto-focus after layout settles. .task auto-cancels on disappear — no leak.
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            focusedField = .host
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("remote_ip_header")
                .font(.title3.bold())

            Text("remote_ip_description \(MyRemoteConstants.defaultPort)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var inputFields: some View {
        VStack(spacing: 12) {
            TextField("hostname_placeholder", text: $host)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .host)
                .submitLabel(.next)
                .onSubmit { focusedField = .port }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            TextField("port_placeholder", text: $portString)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .port)
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var connectButton: some View {
        Button(action: submit) {
            Text("connect_button")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func submit() {
        focusedField = nil  // Dismiss keyboard.
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return }
        let port = UInt16(portString) ?? MyRemoteConstants.defaultPort
        onConnect(trimmedHost, port)
    }
}
