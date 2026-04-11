import Foundation
import Network

/// Connection state for the iOS client.
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case waitingForApproval
    case connected
    case error(String)
}

/// Manages the client-side connection to a MyRemote server.
final class ClientConnection: ObservableObject {

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var sessionToken: String?

    private var connection: NWConnection?
    private let codec = MessageCodec()

    /// Called when a protocol frame arrives from the server.
    var onFrameReceived: ((ProtocolFrame) -> Void)?

    // MARK: - Connect / Disconnect

    func connect(to endpoint: NWEndpoint) {
        state = .connecting
        codec.reset()

        let tlsOptions = NWProtocolTLS.Options()
        // Trust-on-first-use: accept self-signed certs.
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, completionHandler in
                // In production, pin the certificate on first use.
                completionHandler(true)
            },
            .main
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let conn = NWConnection(to: endpoint, using: parameters)

        conn.stateUpdateHandler = { [weak self] connState in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch connState {
                case .ready:
                    self.state = .authenticating
                    self.startReceiving()
                case .failed(let error):
                    self.state = .error("Connection failed: \(error.localizedDescription)")
                case .cancelled:
                    self.state = .disconnected
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .userInteractive))
        connection = conn
    }

    func disconnect() {
        let frame = ProtocolFrame(type: .disconnect)
        send(data: frame.encode())
        connection?.cancel()
        connection = nil
        state = .disconnected
        sessionToken = nil
        codec.reset()
    }

    // MARK: - Authentication

    func sendAuthRequest(password: String) {
        let request = AuthRequest(
            password: password,
            deviceUUID: DeviceIdentity.uuid,
            deviceName: DeviceIdentity.deviceName
        )
        do {
            let data = try MessageCodec.encode(.authRequest, payload: request)
            send(data: data)
            state = .waitingForApproval
        } catch {
            state = .error("Failed to encode auth request: \(error.localizedDescription)")
        }
    }

    // MARK: - Sending

    func send(data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[ClientConnection] Send error: \(error)")
            }
        })
    }

    func sendFrame(_ type: MessageType, payload: Data = Data()) {
        let frame = ProtocolFrame(type: type, payload: payload)
        send(data: frame.encode())
    }

    func sendJSON<T: Encodable>(_ type: MessageType, payload: T) {
        do {
            let data = try MessageCodec.encode(type, payload: payload)
            send(data: data)
        } catch {
            print("[ClientConnection] Encoding error: \(error)")
        }
    }

    /// Request a keyframe from the server.
    func requestKeyframe() {
        sendFrame(.keyframeRequest)
    }

    // MARK: - Receiving

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.codec.append(data)
                let frames = self.codec.decodeAvailableFrames()
                for frame in frames {
                    self.handleFrame(frame)
                }
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.state = .disconnected
                }
                return
            }

            self.startReceiving()
        }
    }

    private func handleFrame(_ frame: ProtocolFrame) {
        switch frame.type {
        case .authResult:
            handleAuthResult(frame)
        case .heartbeat:
            // Respond to heartbeat.
            sendFrame(.heartbeat)
        case .disconnect:
            DispatchQueue.main.async {
                self.state = .disconnected
                self.sessionToken = nil
            }
        default:
            // Forward to external handler (video, config, etc.)
            onFrameReceived?(frame)
        }
    }

    private func handleAuthResult(_ frame: ProtocolFrame) {
        do {
            let result = try MessageCodec.decodePayload(AuthResult.self, from: frame)
            DispatchQueue.main.async {
                if result.success, let token = result.sessionToken {
                    self.sessionToken = token
                    self.state = .connected
                } else {
                    self.state = .error(result.reason ?? "Authentication denied")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.state = .error("Invalid auth response")
            }
        }
    }
}
