import Combine
import Foundation
import os

/// Looks up a pairing code on the signaling server to get the Mac's public IP.
final class PairingCodeLookup: ObservableObject {

    @Published private(set) var isLooking = false
    @Published private(set) var result: PairingLookupResult?
    @Published private(set) var errorMessage: String?

    private let signalingURL: URL

    init(signalingBaseURL: String = "https://myremote-signal.example.com") {
        self.signalingURL = URL(string: signalingBaseURL)!
    }

    /// Look up a pairing code to get the Mac's connection info.
    func lookup(code: String) {
        let cleanCode = PairingCodeGenerator.parse(code)
        guard cleanCode.count == 6 else {
            errorMessage = "Invalid code. Enter a 6-character pairing code."
            return
        }

        isLooking = true
        errorMessage = nil
        result = nil

        let url = signalingURL.appendingPathComponent("api/pairing/\(cleanCode)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLooking = false

                if let error = error {
                    self.errorMessage = "Cannot reach signaling server: \(error.localizedDescription)"
                    Log.pairing.error("Lookup failed: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Empty response from server"
                    return
                }

                do {
                    let lookupResult = try JSONDecoder().decode(PairingLookupResult.self, from: data)
                    if lookupResult.found {
                        self.result = lookupResult
                        self.errorMessage = nil
                        Log.pairing.info("Found Mac at \(lookupResult.publicIP ?? "?"):\(lookupResult.port ?? 0)")
                    } else {
                        self.errorMessage = lookupResult.error ?? "Code not found. Check the code on your Mac."
                    }
                } catch {
                    self.errorMessage = "Invalid response from server"
                }
            }
        }.resume()
    }

    func reset() {
        isLooking = false
        result = nil
        errorMessage = nil
    }
}
