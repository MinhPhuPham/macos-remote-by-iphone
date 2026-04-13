import Combine
import Foundation
import JPMacIPRemoteShared
import os

/// Manages the pairing code lifecycle on the macOS server.
/// Generates a code, registers it with the signaling server,
/// and periodically refreshes the registration (keep-alive).
final class PairingCodeManager: ObservableObject {

    @Published private(set) var currentCode: String = ""
    @Published private(set) var formattedCode: String = ""
    @Published private(set) var isRegistered = false
    @Published private(set) var errorMessage: String?

    private let port: UInt16
    private let signalingURL: URL
    private let apiKey: String
    private var refreshTimer: DispatchSourceTimer?

    /// How often to refresh the registration (keep-alive). Server expires entries after 2x this.
    private let refreshInterval: TimeInterval = 30

    init(port: UInt16 = MyRemoteConstants.defaultPort,
         signalingBaseURL: String = "https://myremote-signal.example.com",
         apiKey: String = "") {
        self.port = port
        self.signalingURL = URL(string: signalingBaseURL)!
        self.apiKey = apiKey
    }

    // MARK: - Generate & Register

    /// Generate a new pairing code and register it with the signaling server.
    func generateAndRegister() {
        let code = PairingCodeGenerator.generate()
        currentCode = code
        formattedCode = PairingCodeGenerator.format(code)
        register(code: code)
    }

    /// Re-register the current code (e.g., after IP change).
    func refresh() {
        guard !currentCode.isEmpty else { return }
        register(code: currentCode)
    }

    /// Stop advertising the pairing code.
    func unregister() {
        stopRefreshTimer()
        guard !currentCode.isEmpty else { return }

        let url = signalingURL.appendingPathComponent("api/pairing/\(currentCode)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Best-effort unregister.
        }.resume()

        DispatchQueue.main.async {
            self.isRegistered = false
        }
    }

    // MARK: - Registration

    private func register(code: String) {
        let hostname = ProcessInfo.processInfo.hostName
        let registration = PairingRegistration(
            code: code,
            publicIP: nil, // Server detects from request IP.
            port: port,
            hostname: hostname
        )

        let url = signalingURL.appendingPathComponent("api/pairing")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        do {
            request.httpBody = try JSONEncoder().encode(registration)
        } catch {
            DispatchQueue.main.async { self.errorMessage = "Failed to encode registration" }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.isRegistered = false
                    self.errorMessage = "Signaling server unreachable: \(error.localizedDescription)"
                    Log.pairing.error("Registration failed: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self.isRegistered = false
                    self.errorMessage = "Registration failed (server error)"
                    return
                }

                self.isRegistered = true
                self.errorMessage = nil
                self.startRefreshTimer()
                Log.pairing.info("Registered pairing code: \(self.formattedCode)")
            }
        }.resume()
    }

    // MARK: - Keep-Alive Timer

    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    deinit {
        stopRefreshTimer()
    }
}
