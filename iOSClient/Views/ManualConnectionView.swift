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
        VStack(spacing: 24) {
            header

            inputFields

            connectButton
        }
        .padding(32)
        .navigationTitle("Manual Connect")
        .onAppear { focusedField = .host }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Connect over Internet")
                .font(.title2.bold())

            Text("Enter your Mac's public IP address or hostname.\nMake sure port \(MyRemoteConstants.defaultPort) is forwarded on your router.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var inputFields: some View {
        VStack(spacing: 12) {
            TextField("Hostname or IP address", text: $host)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .host)
                .submitLabel(.next)
                .onSubmit { focusedField = .port }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Server hostname or IP address")

            TextField("Port", text: $portString)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .port)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Server port number")
        }
    }

    private var connectButton: some View {
        Button(action: submit) {
            Text("Connect")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityHint("Connects to the Mac over the internet")
    }

    private func submit() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return }
        let port = UInt16(portString) ?? MyRemoteConstants.defaultPort
        onConnect(trimmedHost, port)
    }
}
