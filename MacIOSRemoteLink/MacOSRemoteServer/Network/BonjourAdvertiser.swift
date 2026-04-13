import Combine
import Foundation
import Network
import os
import Security

/// Advertises the MyRemote server via Bonjour and accepts incoming TCP connections.
/// Uses plain TCP for now (TLS requires a valid identity from the Keychain).
final class BonjourAdvertiser: ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private var listener: NWListener?
    private let port: UInt16

    /// Called when a new client connection is received.
    var onNewConnection: ((NWConnection) -> Void)?

    init(port: UInt16 = MyRemoteConstants.defaultPort) {
        self.port = port
    }

    // MARK: - Start / Stop

    func start(tlsIdentity: SecIdentity?) {
        do {
            let parameters: NWParameters

            if let identity = tlsIdentity, let secIdentity = sec_identity_create(identity) {
                // Use TLS with the provided identity.
                let tlsOptions = NWProtocolTLS.Options()
                sec_protocol_options_set_local_identity(
                    tlsOptions.securityProtocolOptions,
                    secIdentity
                )
                sec_protocol_options_set_min_tls_protocol_version(
                    tlsOptions.securityProtocolOptions,
                    .TLSv13
                )
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveIdle = 30
                parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
                Log.bonjour.info("Starting listener with TLS")
            } else {
                // Fall back to plain TCP — connections still work, just unencrypted.
                // This is acceptable for local WiFi during development.
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveIdle = 30
                parameters = NWParameters(tls: nil, tcp: tcpOptions)
                Log.bonjour.info("Starting listener with plain TCP (no TLS identity)")
            }

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                errorMessage = "Invalid port: \(port)"
                return
            }
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            errorMessage = "Failed to create listener: \(error.localizedDescription)"
            return
        }

        // Advertise via Bonjour.
        listener?.service = NWListener.Service(
            name: "MyRemote",
            type: MyRemoteConstants.bonjourServiceType
        )

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isListening = true
                    self?.errorMessage = nil
                    Log.bonjour.info("Server listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.isListening = false
                    self?.errorMessage = "Listener failed: \(error.localizedDescription)"
                    Log.bonjour.error("Listener failed: \(error.localizedDescription)")
                case .cancelled:
                    self?.isListening = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Log.bonjour.info("New incoming connection from \(connection.endpoint.debugDescription)")
            self?.onNewConnection?(connection)
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }
}

