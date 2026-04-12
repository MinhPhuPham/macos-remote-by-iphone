import SwiftUI

/// Enter a 6-character pairing code to find and connect to a Mac over the internet.
struct PairingCodeView: View {

    let onConnect: (String, UInt16) -> Void

    @StateObject private var lookup = PairingCodeLookup()
    @State private var codeInput = ""
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            header

            codeField

            if lookup.isLooking {
                lookingView
            } else if let result = lookup.result, let ip = result.publicIP, let port = result.port {
                foundView(hostname: result.hostname ?? ip, ip: ip, port: port)
            } else {
                lookupButton
            }

            if let error = lookup.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .navigationTitle("Pairing Code")
        .onAppear { isCodeFocused = true }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Enter Pairing Code")
                .font(.title2.bold())

            Text("Enter the 6-character code shown\non your Mac's MyRemote menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var codeField: some View {
        TextField("ABC-123", text: $codeInput)
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($isCodeFocused)
            .submitLabel(.search)
            .onSubmit { performLookup() }
            .onChange(of: codeInput) { _, newValue in
                // Auto-format: insert dash after 3 chars.
                let clean = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                if clean.count > 6 {
                    codeInput = String(clean.prefix(6))
                } else if clean.count > 3 && !newValue.contains("-") {
                    let idx = clean.index(clean.startIndex, offsetBy: 3)
                    codeInput = "\(clean[..<idx])-\(clean[idx...])"
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Pairing code")
    }

    private var lookupButton: some View {
        Button(action: performLookup) {
            Text("Find My Mac")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(cleanCode.count < 6)
    }

    private var lookingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Looking up code...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func foundView(hostname: String, ip: String, port: UInt16) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.title)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hostname)
                        .font(.headline)
                    Text("\(ip):\(port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                onConnect(ip, port)
            } label: {
                Text("Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Logic

    private var cleanCode: String {
        PairingCodeGenerator.parse(codeInput)
    }

    private func performLookup() {
        guard cleanCode.count == 6 else { return }
        lookup.lookup(code: cleanCode)
    }
}
