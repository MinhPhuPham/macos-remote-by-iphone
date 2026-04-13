import Combine
import Foundation
import Network
import os

/// Connection state for the iOS client.
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case waitingForApproval
    case connected
    case reconnecting(attempt: Int)
    case error(String)
}

/// Manages the client-side connection to a MyRemote server.
/// Supports both LAN (Bonjour) and WAN (manual IP/hostname) connections.
final class ClientConnection: ObservableObject {

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var sessionToken: String?
    @Published var connectionMode: ConnectionMode = .lan

    private var connection: NWConnection?
    private let codec = MessageCodec()
    let qualityMonitor: NetworkQualityMonitor

    var onFrameReceived: ((ProtocolFrame) -> Void)?

    // Reconnection state.
    private var lastEndpoint: NWEndpoint?
    private var lastPassword: String?
    private var reconnectAttempt = 0
    private var reconnectTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?

    init() {
        self.qualityMonitor = NetworkQualityMonitor(mode: .lan)
    }

    // MARK: - Connect

    /// Connect via Bonjour endpoint (LAN discovery).
    func connect(to endpoint: NWEndpoint) {
        Log.connection.debug("Connecting via Bonjour: \(endpoint.debugDescription)")
        connectionMode = .lan
        qualityMonitor.setMode(.lan)
        lastEndpoint = endpoint
        startConnection(to: endpoint)
    }

    /// Connect via manual hostname/IP and port (WAN/cellular).
    func connect(host: String, port: UInt16) {
        Log.connection.debug("Connecting via IP: \(host):\(port)")
        connectionMode = .wan
        qualityMonitor.setMode(.wan)
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: MyRemoteConstants.defaultPort)!
        )
        lastEndpoint = endpoint
        startConnection(to: endpoint)
    }

    private func startConnection(to endpoint: NWEndpoint) {
        Log.connection.info("Connecting to \(endpoint.debugDescription)")
        state = .connecting
        codec.reset()

        // Use plain TCP to match the server (which starts without a TLS identity).
        // TODO: Add TLS when self-signed certificate generation is implemented.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = connectionMode == .wan ? 15 : 30

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let conn = NWConnection(to: endpoint, using: parameters)

        conn.stateUpdateHandler = { [weak self] connState in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch connState {
                case .ready:
                    Log.connection.info("TCP connection ready — authenticating")
                    self.state = .authenticating
                    self.reconnectAttempt = 0
                    self.startReceiving()
                    self.startClientHeartbeat()
                    self.qualityMonitor.startMonitoring()
                case .failed(let error):
                    self.handleConnectionFailure(error)
                case .cancelled:
                    Log.connection.info("Disconnected")
                    self.state = .disconnected
                case .waiting(let error):
                    // Network path not available (e.g., no connectivity).
                    Log.connection.info("Connection waiting: \(error.localizedDescription)")
                default:
                    break
                }
            }
        }

        // Monitor network path changes (WiFi ↔ cellular transitions).
        conn.pathUpdateHandler = { path in
            Log.connection.info("Network path updated: \(path.debugDescription)")
        }

        conn.start(queue: .global(qos: .userInteractive))
        connection = conn
    }

    // MARK: - Disconnect

    func disconnect() {
        Log.connection.debug("Disconnecting — cleaning up")
        stopReconnectTimer()
        stopClientHeartbeat()
        qualityMonitor.stopMonitoring()

        // Capture connection locally before niling the property,
        // so the send callback can still cancel it.
        let conn = connection
        let frame = ProtocolFrame(type: .disconnect)
        let data = frame.encode()
        conn?.send(content: data, completion: .contentProcessed { _ in
            conn?.cancel()
        })
        connection = nil
        state = .disconnected
        sessionToken = nil
        lastPassword = nil
        codec.reset()
    }

    // MARK: - Authentication

    func sendAuthRequest(password: String) {
        Log.connection.debug("Sending auth request for device \(DeviceIdentity.deviceName)")
        lastPassword = password
        let request = AuthRequest(
            password: password,
            deviceUUID: DeviceIdentity.uuid,
            deviceName: DeviceIdentity.deviceName
        )
        do {
            let data = try MessageCodec.encode(.authRequest, payload: request)
            sendRaw(data: data)
            state = .waitingForApproval
        } catch {
            state = .error("Failed to encode auth request: \(error.localizedDescription)")
        }
    }

    // MARK: - Sending

    private func sendRaw(data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                Log.connection.warning("Send error: \(error.localizedDescription)")
            }
        })
    }

    func sendFrame(_ type: MessageType, payload: Data = Data()) {
        let frame = ProtocolFrame(type: type, payload: payload)
        sendRaw(data: frame.encode())
    }

    func sendJSON<T: Encodable>(_ type: MessageType, payload: T) {
        do {
            let data = try MessageCodec.encode(type, payload: payload)
            sendRaw(data: data)
        } catch {
            Log.connection.error("Encoding error: \(error.localizedDescription)")
        }
    }

    func requestKeyframe() {
        sendFrame(.keyframeRequest)
    }

    // MARK: - Client-Side Heartbeat

    private func startClientHeartbeat() {
        stopClientHeartbeat()
        let interval = connectionMode.heartbeatInterval
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendFrame(.heartbeat)
        }
        timer.resume()
        heartbeatTimer = timer

        // Wire up ping sending for RTT measurement.
        qualityMonitor.sendPing = { [weak self] in
            let ping = PingPayload()
            self?.sendJSON(.ping, payload: ping)
        }

        // Wire up quality change requests.
        qualityMonitor.onQualityChange = { [weak self] bitrate, fps in
            let update = QualityUpdate(requestedBitrate: bitrate, requestedFPS: fps)
            self?.sendJSON(.qualityUpdate, payload: update)
        }
    }

    private func stopClientHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: - Auto-Reconnect (Exponential Backoff)

    private func handleConnectionFailure(_ error: NWError) {
        stopClientHeartbeat()
        qualityMonitor.stopMonitoring()

        let isTransient = isTransientError(error)

        if isTransient, reconnectAttempt < MyRemoteConstants.maxReconnectRetries, lastEndpoint != nil {
            reconnectAttempt += 1
            state = .reconnecting(attempt: reconnectAttempt)
            scheduleReconnect()
        } else {
            state = .error("Connection failed: \(error.localizedDescription)")
        }
    }

    private func isTransientError(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            // Network unreachable, host unreachable, connection reset, timeout.
            return [.ENETUNREACH, .EHOSTUNREACH, .ECONNRESET, .ETIMEDOUT, .ECONNREFUSED].contains(code)
        case .tls:
            return false // TLS errors are not transient.
        default:
            return true
        }
    }

    private func scheduleReconnect() {
        guard let endpoint = lastEndpoint else { return }

        let delay = MyRemoteConstants.reconnectBaseDelay * pow(2.0, Double(reconnectAttempt - 1))
        let cappedDelay = min(delay, 30.0) // Cap at 30 seconds.
        Log.connection.info("Reconnecting in \(Int(cappedDelay))s (attempt \(self.reconnectAttempt)/\(MyRemoteConstants.maxReconnectRetries))")

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + cappedDelay)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.startConnection(to: endpoint)
            // If we had a session, re-authenticate automatically.
            if let password = self.lastPassword {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if self?.state == .authenticating {
                        self?.sendAuthRequest(password: password)
                    }
                }
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectAttempt = 0
    }

    // MARK: - Receiving

    private func startReceiving() {
        Log.connection.debug("Receive loop started")
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                guard self.codec.append(data) else {
                    Log.connection.warning("Buffer overflow — disconnecting")
                    self.disconnect()
                    return
                }
                let frames = self.codec.decodeAvailableFrames()
                for frame in frames {
                    self.handleFrame(frame)
                }
            }

            if isComplete || error != nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let error = error {
                        self.handleConnectionFailure(error)
                    } else {
                        self.state = .disconnected
                    }
                }
                return
            }

            self.startReceiving()
        }
    }

    private var videoFrameCount = 0

    private func handleFrame(_ frame: ProtocolFrame) {
        switch frame.type {
        case .authResult:
            Log.connection.info("Received: authResult")
            handleAuthResult(frame)
        case .heartbeat:
            sendFrame(.heartbeat)
        case .pong:
            if let payload = try? MessageCodec.decodePayload(PingPayload.self, from: frame) {
                qualityMonitor.receivedPong(payload: payload)
            }
        case .videoFrame:
            videoFrameCount += 1
            if videoFrameCount <= 3 || videoFrameCount % 100 == 0 {
                Log.connection.debug("Received: videoFrame #\(self.videoFrameCount) (\(frame.payload.count)B)")
            }
            onFrameReceived?(frame)
        case .videoConfig:
            Log.connection.info("Received: videoConfig (\(frame.payload.count)B)")
            onFrameReceived?(frame)
        case .configUpdate:
            Log.connection.info("Received: configUpdate")
            onFrameReceived?(frame)
        case .disconnect:
            Log.connection.info("Received: disconnect")
            DispatchQueue.main.async { [weak self] in
                self?.state = .disconnected
                self?.sessionToken = nil
            }
        default:
            Log.connection.debug("Received: unknown type \(frame.type.rawValue)")
            onFrameReceived?(frame)
        }
    }

    private func handleAuthResult(_ frame: ProtocolFrame) {
        do {
            let result = try MessageCodec.decodePayload(AuthResult.self, from: frame)
            Log.connection.debug("Auth result: success=\(result.success) reason=\(result.reason ?? "none")")
            DispatchQueue.main.async { [weak self] in
                if result.success, let token = result.sessionToken {
                    Log.connection.info("Authenticated — session started")
                    self?.sessionToken = token
                    self?.state = .connected
                } else {
                    self?.state = .error(result.reason ?? "Authentication denied")
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.state = .error("Invalid auth response")
            }
        }
    }
}
