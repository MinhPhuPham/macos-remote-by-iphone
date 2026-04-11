import Foundation
import Network

/// Advertises the MyRemote server via Bonjour and accepts incoming TLS connections.
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
            let parameters = createParameters(identity: tlsIdentity)
            let nwPort = NWEndpoint.Port(rawValue: port)!
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
                case .failed(let error):
                    self?.isListening = false
                    self?.errorMessage = "Listener failed: \(error.localizedDescription)"
                case .cancelled:
                    self?.isListening = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.onNewConnection?(connection)
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    // MARK: - TLS Parameters

    private func createParameters(identity: SecIdentity?) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        if let identity = identity {
            let secIdentity = sec_identity_create(identity)!
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions,
                secIdentity
            )
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions,
                .TLSv13
            )
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30

        return NWParameters(tls: tlsOptions, tcp: tcpOptions)
    }
}
