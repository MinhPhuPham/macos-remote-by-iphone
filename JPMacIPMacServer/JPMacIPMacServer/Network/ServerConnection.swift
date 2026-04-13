import Combine
import Foundation
import JPMacIPRemoteShared
import Network
import os

/// Manages a single client connection on the server side.
final class ServerConnection: ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var remoteAddress: String = "unknown"

    let connection: NWConnection
    private let codec = MessageCodec()

    var onFrameReceived: ((ProtocolFrame, ServerConnection) -> Void)?
    var onDisconnected: ((ServerConnection) -> Void)?

    /// Set to true once the client has authenticated. Used by the auth timeout.
    var isAuthenticated = false

    private var heartbeatTimer: DispatchSourceTimer?
    private var authTimeoutTimer: DispatchSourceTimer?
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
                    self.startAuthTimeout()
                case .failed, .cancelled:
                    self.isConnected = false
                    self.stopHeartbeat()
                    self.cancelAuthTimeout()
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
        cancelAuthTimeout()
        connection.cancel()
    }

    // MARK: - Sending

    func send(frame: ProtocolFrame) {
        let data = frame.encode()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                Log.connection.warning("Send error: \(error.localizedDescription)")
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
                    Log.connection.warning("Send error: \(error.localizedDescription)")
                }
            })
        } catch {
            Log.connection.error("Encoding error: \(error.localizedDescription)")
        }
    }

    // MARK: - Receiving

    private func startReceiving() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                guard self.codec.append(data) else {
                    Log.connection.warning("Buffer overflow — disconnecting client \(self.remoteAddress)")
                    self.disconnect()
                    return
                }
                self.lastActivityDate = Date()
                let frames = self.codec.decodeAvailableFrames()
                for frame in frames {
                    self.onFrameReceived?(frame, self)
                }
            }

            if isComplete || error != nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isConnected = false
                    self.stopHeartbeat()
                    self.onDisconnected?(self)
                }
                return
            }

            self.startReceiving()
        }
    }

    // MARK: - Heartbeat (DispatchSourceTimer, no RunLoop dependency)

    private func startHeartbeat() {
        // Use WAN interval as default since server doesn't know client's network type.
        // Client also sends its own heartbeats at its preferred interval.
        let interval = MyRemoteConstants.WAN.heartbeatInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.send(frame: ProtocolFrame(type: .heartbeat))
            self.checkSessionTimeout()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func checkSessionTimeout() {
        let elapsed = Date().timeIntervalSince(lastActivityDate)
        if elapsed > MyRemoteConstants.sessionTimeoutInterval {
            Log.connection.info("Session timeout, disconnecting.")
            disconnect()
        }
    }

    // MARK: - Auth Timeout

    /// Disconnect if client hasn't authenticated within the timeout period.
    private func startAuthTimeout() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + MyRemoteConstants.authTimeoutInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if !self.isAuthenticated {
                Log.connection.info("Auth timeout — disconnecting unauthenticated client \(self.remoteAddress)")
                self.disconnect()
            }
        }
        timer.resume()
        authTimeoutTimer = timer
    }

    private func cancelAuthTimeout() {
        authTimeoutTimer?.cancel()
        authTimeoutTimer = nil
    }

    var clientIP: String {
        remoteAddress
    }
}
