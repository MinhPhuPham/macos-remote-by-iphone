import Foundation
import Network

/// Manages a single client connection on the server side.
/// Handles reading frames, dispatching to handlers, and sending responses.
final class ServerConnection: ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var remoteAddress: String = ""

    let connection: NWConnection
    private let codec = MessageCodec()

    /// Called when a complete protocol frame is received.
    var onFrameReceived: ((ProtocolFrame, ServerConnection) -> Void)?
    /// Called when the connection is lost or closed.
    var onDisconnected: ((ServerConnection) -> Void)?

    private var heartbeatTimer: Timer?
    private var lastActivityDate = Date()

    init(connection: NWConnection) {
        self.connection = connection
        if case let .hostPort(host, _) = connection.endpoint {
            remoteAddress = "\(host)"
        }
    }

    // MARK: - Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isConnected = true
                    self.startReceiving()
                    self.startHeartbeat()
                case .failed, .cancelled:
                    self.isConnected = false
                    self.stopHeartbeat()
                    self.onDisconnected?(self)
                default:
                    break
                }
            }
        }
        connection.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        send(frame: ProtocolFrame(type: .disconnect))
        stopHeartbeat()
        connection.cancel()
    }

    // MARK: - Sending

    func send(frame: ProtocolFrame) {
        let data = frame.encode()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[ServerConnection] Send error: \(error)")
            }
        })
    }

    func send(type: MessageType, payload: Data = Data()) {
        send(frame: ProtocolFrame(type: type, payload: payload))
    }

    func sendJSON<T: Encodable>(_ type: MessageType, payload: T) {
        do {
            let data = try MessageCodec.encode(type, payload: payload)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("[ServerConnection] Send error: \(error)")
                }
            })
        } catch {
            print("[ServerConnection] Encoding error: \(error)")
        }
    }

    // MARK: - Receiving

    private func startReceiving() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.codec.append(data)
                self.lastActivityDate = Date()
                let frames = self.codec.decodeAvailableFrames()
                for frame in frames {
                    self.onFrameReceived?(frame, self)
                }
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.stopHeartbeat()
                    self.onDisconnected?(self)
                }
                return
            }

            // Continue receiving.
            self.startReceiving()
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: MyRemoteConstants.heartbeatInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.send(frame: ProtocolFrame(type: .heartbeat))
            self.checkSessionTimeout()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func checkSessionTimeout() {
        let elapsed = Date().timeIntervalSince(lastActivityDate)
        if elapsed > MyRemoteConstants.sessionTimeoutInterval {
            print("[ServerConnection] Session timeout, disconnecting.")
            disconnect()
        }
    }

    /// IP address of the remote client.
    var clientIP: String {
        remoteAddress
    }
}
