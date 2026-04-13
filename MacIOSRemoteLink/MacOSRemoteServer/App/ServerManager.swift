import AppKit
import Combine
import Foundation
import Network
import os

/// Central coordinator for the macOS server.
/// Manages networking, auth flow, client connections, and streaming state.
final class ServerManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Server stopped"
    @Published private(set) var connectedClient: ServerConnection?
    @Published private(set) var pendingApproval: PendingApproval?
    @Published var streamQuality: StreamQuality = .medium

    /// A device waiting for user approval.
    struct PendingApproval {
        let deviceName: String
        let deviceUUID: String
        let clientIP: String
        let client: ServerConnection
    }

    enum StreamQuality: String, CaseIterable, Identifiable {
        case low, medium, high
        var id: String { rawValue }

        func bitrate(for mode: ConnectionMode) -> Int {
            switch self {
            case .low:    return mode.lowBitrate
            case .medium: return mode.defaultBitrate
            case .high:   return mode.highBitrate
            }
        }
    }

    var statusIcon: String {
        if connectedClient != nil { return "circle.fill" }
        if isRunning { return "circle.dotted" }
        return "circle"
    }

    // MARK: - Dependencies

    let authManager: AuthManager
    let trustedDeviceStore: TrustedDeviceStore
    private let advertiser: BonjourAdvertiser
    private let mouseInjector = MouseInjector()
    private let keyboardInjector = KeyboardInjector()

    // MARK: - Video Pipeline

    private var captureManager: ScreenCaptureManager?
    private var videoEncoder: VideoEncoder?

    /// Holds the client while waiting for auth. Without this, the ServerConnection
    /// created in handleIncomingConnection would be deallocated immediately
    /// (local variable, only weak refs in closures).
    private var pendingClient: ServerConnection?

    /// Track whether we've logged the first successful input validation (avoid spamming).
    private var hasLoggedFirstInput = false

    // MARK: - Init

    init() {
        let store = TrustedDeviceStore()
        self.trustedDeviceStore = store
        self.authManager = AuthManager(trustedDeviceStore: store)
        self.advertiser = BonjourAdvertiser()

        advertiser.onNewConnection = { [weak self] nwConnection in
            self?.handleIncomingConnection(nwConnection)
        }

        // Auto-start the server on launch.
        start()
    }

    // MARK: - Server Lifecycle

    func start() {
        if authManager.currentPassword() == nil {
            do {
                try authManager.generatePIN()
                Log.app.info("Generated initial PIN (check Settings to view)")
            } catch {
                Log.app.error("Failed to generate PIN: \(error.localizedDescription)")
            }
        }
        advertiser.start(tlsIdentity: nil)
        isRunning = true
        Log.app.info("Server started on port \(MyRemoteConstants.defaultPort)")
        statusMessage = "Waiting for connections..."
    }

    func stop() {
        stopVideoPipeline()
        connectedClient?.disconnect()
        connectedClient = nil
        advertiser.stop()
        authManager.endSession()
        isRunning = false
        Log.app.info("Server stopped")
        statusMessage = "Server stopped"
    }

    // MARK: - Incoming Connection

    private func handleIncomingConnection(_ nwConnection: NWConnection) {
        Log.connection.info("New connection from \(nwConnection.endpoint.debugDescription)")

        // If there's a stale session (client disconnected without proper cleanup),
        // check if the connected client is still alive. If not, clean up and allow.
        if authManager.hasActiveSession {
            if let existing = connectedClient, existing.isConnected {
                Log.connection.info("Rejecting connection — active session exists")
                nwConnection.cancel()
                return
            }
            // Stale session — clean up before accepting new connection.
            Log.connection.warning("Stale session detected — cleaning up")
            handleClientDisconnected()
        }

        // Reject if we already have a pending client (dual-address scenario:
        // iPhone resolves Bonjour to multiple IPs, listener receives both).
        if pendingClient != nil {
            Log.connection.info("Rejecting — pending auth already in progress")
            nwConnection.cancel()
            return
        }

        let client = ServerConnection(connection: nwConnection)
        pendingClient = client  // Retain until auth completes or connection drops.

        client.onFrameReceived = { [weak self] frame, conn in
            self?.handleFrame(frame, from: conn)
        }

        client.onDisconnected = { [weak self] disconnectedClient in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Only full cleanup if this was the authenticated client.
                if self.connectedClient === disconnectedClient {
                    self.handleClientDisconnected()
                }
                // Clear pending ref if it matches (unauthenticated disconnect).
                if self.pendingClient === disconnectedClient {
                    Log.connection.info("Pending client disconnected before auth")
                    self.pendingClient = nil
                }
            }
        }

        client.start()
    }

    // MARK: - Frame Handling

    private func handleFrame(_ frame: ProtocolFrame, from client: ServerConnection) {
        switch frame.type {
        case .authRequest:
            handleAuthRequest(frame, from: client)
        case .mouseEvent:
            handleInputEvent(frame, handler: handleMouseEvent)
        case .keyEvent:
            handleInputEvent(frame, handler: handleKeyEvent)
        case .scrollEvent:
            handleInputEvent(frame, handler: handleScrollEvent)
        case .keyframeRequest:
            videoEncoder?.forceKeyframe()
        case .heartbeat:
            break
        case .ping:
            // RTT measurement: echo back with same timestamp.
            client.send(frame: ProtocolFrame(type: .pong, payload: frame.payload))
        case .qualityUpdate:
            handleQualityUpdate(frame)
        case .disconnect:
            DispatchQueue.main.async { [weak self] in self?.handleClientDisconnected() }
        default:
            Log.connection.debug("Unhandled frame type: \(frame.type.rawValue)")
        }
    }

    private func handleQualityUpdate(_ frame: ProtocolFrame) {
        guard let update = try? MessageCodec.decodePayload(QualityUpdate.self, from: frame) else { return }
        Log.app.info("Client requested quality: bitrate=\(update.requestedBitrate), fps=\(update.requestedFPS)")
        videoEncoder?.setBitrate(update.requestedBitrate)
        videoEncoder?.setFrameRate(update.requestedFPS)
    }

    /// Validate session token before processing an input event.
    private func handleInputEvent(_ frame: ProtocolFrame, handler: (ProtocolFrame) -> Void) {
        // Extract session token from JSON payload for validation.
        struct TokenCheck: Decodable { let sessionToken: String }
        guard let check = try? MessageCodec.decodePayload(TokenCheck.self, from: frame),
              authManager.validateSession(check.sessionToken) else {
            Log.app.warning("Rejected input event with invalid session token")
            return
        }
        if !hasLoggedFirstInput {
            Log.app.debug("First input event validated — session token OK")
            hasLoggedFirstInput = true
        }
        handler(frame)
    }

    private func handleMouseEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(MouseEvent.self, from: frame) else { return }
        // Validate coordinates.
        guard event.x.isFinite, event.y.isFinite, event.x >= 0, event.y >= 0 else { return }
        Log.input.debug("Mouse \(event.type.rawValue) at (\(event.x), \(event.y))")
        mouseInjector.inject(event: event)
    }

    private func handleKeyEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(KeyEvent.self, from: frame) else { return }
        Log.input.debug("Key \(event.keyCode) \(event.isDown ? "down" : "up")")
        keyboardInjector.inject(event: event)
    }

    private func handleScrollEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(ScrollEvent.self, from: frame) else { return }
        guard event.deltaX.isFinite, event.deltaY.isFinite else { return }
        Log.input.debug("Scroll deltaX=\(event.deltaX) deltaY=\(event.deltaY)")
        mouseInjector.scroll(deltaX: Int32(event.deltaX), deltaY: Int32(event.deltaY))
    }

    // MARK: - Auth Flow

    private func handleAuthRequest(_ frame: ProtocolFrame, from client: ServerConnection) {
        guard let request = try? MessageCodec.decodePayload(AuthRequest.self, from: frame) else {
            Log.auth.warning("Received malformed auth request")
            let result = AuthResult(success: false, reason: "Invalid request format")
            client.sendJSON(.authResult, payload: result)
            return
        }

        let clientIP = client.clientIP
        let deviceUUID = request.deviceUUID
        Log.auth.info("Auth request from \"\(request.deviceName)\" (\(clientIP))")

        // Dual rate limiting: check both IP and device UUID.
        let blockCheck = authManager.isBlocked(ip: clientIP, deviceUUID: deviceUUID)
        if blockCheck.blocked {
            Log.auth.warning("Blocked auth attempt from \(clientIP): \(blockCheck.reason ?? "rate limited")")
            let result = AuthResult(success: false, reason: blockCheck.reason ?? "Too many attempts.")
            client.sendJSON(.authResult, payload: result)
            return
        }

        guard authManager.validatePassword(request.password) else {
            Log.auth.info("Invalid password from \"\(request.deviceName)\" (\(clientIP))")
            authManager.recordFailedAttempt(ip: clientIP, deviceUUID: deviceUUID)
            let result = AuthResult(success: false, reason: "Invalid password")
            client.sendJSON(.authResult, payload: result)
            return
        }

        Log.auth.info("Password valid for \"\(request.deviceName)\" — checking trust")
        authManager.clearFailedAttempts(ip: clientIP, deviceUUID: deviceUUID)
        client.isAuthenticated = true

        if authManager.deviceIsTrusted(request.deviceUUID) {
            Log.auth.info("Device trusted — granting access automatically")
            DispatchQueue.main.async { [weak self] in
                self?.grantAccess(to: client, deviceName: request.deviceName)
            }
            return
        }

        Log.auth.info("Device not trusted — showing approval dialog")
        DispatchQueue.main.async { [weak self] in
            self?.showConfirmationDialog(
                deviceName: request.deviceName,
                deviceUUID: request.deviceUUID,
                clientIP: clientIP,
                client: client
            )
        }
    }

    private func showConfirmationDialog(
        deviceName: String,
        deviceUUID: String,
        clientIP: String,
        client: ServerConnection
    ) {
        // Sanitize device name: truncate and strip control characters.
        let sanitizedName = String(
            deviceName.prefix(50).unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }
        )

        Log.app.info("Pending approval for \"\(sanitizedName)\" (\(clientIP))")
        pendingApproval = PendingApproval(
            deviceName: sanitizedName,
            deviceUUID: deviceUUID,
            clientIP: clientIP,
            client: client
        )
    }

    /// Called from the UI when the user taps Allow.
    func approveConnection(trustPermanently: Bool) {
        guard let pending = pendingApproval else { return }
        if trustPermanently {
            trustedDeviceStore.trust(deviceUUID: pending.deviceUUID, deviceName: pending.deviceName)
        }
        pendingApproval = nil
        grantAccess(to: pending.client, deviceName: pending.deviceName)
    }

    /// Called from the UI when the user taps Deny.
    func denyConnection() {
        guard let pending = pendingApproval else { return }
        let result = AuthResult(success: false, reason: "Connection denied by user")
        pending.client.sendJSON(.authResult, payload: result)
        pending.client.disconnect()
        pendingApproval = nil
        pendingClient = nil
        Log.app.info("Connection denied for \"\(pending.deviceName)\"")
    }

    /// Must be called on the main thread (all callers dispatch to main).
    private func grantAccess(to client: ServerConnection, deviceName: String) {
        guard let token = authManager.createSession(deviceName: deviceName) else {
            let result = AuthResult(success: false, reason: "Internal server error")
            client.sendJSON(.authResult, payload: result)
            return
        }

        let result = AuthResult(success: true, sessionToken: token)
        client.sendJSON(.authResult, payload: result)

        pendingClient = nil  // Ownership moves to connectedClient.
        connectedClient = client
        statusMessage = "Connected to \(deviceName)"
        Log.app.info("Access granted to \"\(deviceName)\" — starting video pipeline")
        startVideoPipeline(for: client)
    }

    private func handleClientDisconnected() {
        stopVideoPipeline()
        connectedClient = nil
        authManager.endSession()
        hasLoggedFirstInput = false
        statusMessage = isRunning ? "Waiting for connections..." : "Server stopped"
        Log.app.info("Client disconnected")
    }

    // MARK: - Video Pipeline

    private func startVideoPipeline(for client: ServerConnection) {
        Log.capture.info("Creating capture manager")
        let capture = ScreenCaptureManager()
        self.captureManager = capture

        Task {
            do {
                // 0.75× balances quality vs latency on LAN.
                // Full 1.0× creates frames too large for low-latency streaming.
                let scale = MyRemoteConstants.LAN.defaultScaleFactor
                try await capture.startCapture(scaleFactor: CGFloat(scale))
                Log.capture.info("Capture started: \(capture.displayWidth)x\(capture.displayHeight) at \(scale)x")

                let scaledWidth = Int(Double(capture.displayWidth) * scale)
                let scaledHeight = Int(Double(capture.displayHeight) * scale)
                let encoder = VideoEncoder(width: scaledWidth, height: scaledHeight)
                Log.encoder.info("Encoder created: \(scaledWidth)x\(scaledHeight)")

                // Wire: encoder SPS/PPS config → client
                encoder.onVideoConfig = { [weak client] sps, pps in
                    var configData = Data()
                    var spsLength = UInt32(sps.count).bigEndian
                    configData.append(Data(bytes: &spsLength, count: 4))
                    configData.append(sps)
                    configData.append(pps)
                    client?.send(type: .videoConfig, payload: configData)
                    Log.encoder.info("Sent video config: SPS=\(sps.count)B PPS=\(pps.count)B")
                }

                // Wire: encoded frames → client
                encoder.onEncodedFrame = { [weak client] data, isKeyframe in
                    client?.send(type: .videoFrame, payload: data)
                }

                Log.capture.info("Wiring capture → encoder → client")

                // Wire: captured pixels → encoder
                capture.onPixelBuffer = { [weak encoder] pixelBuffer, timestamp in
                    encoder?.encode(pixelBuffer: pixelBuffer, presentationTime: timestamp)
                }

                let bitrate = streamQuality.bitrate(for: .lan)
                let fps = MyRemoteConstants.LAN.defaultFrameRate
                try encoder.start(bitrate: bitrate, frameRate: fps)

                await MainActor.run {
                    self.videoEncoder = encoder
                }

                // Send screen dimensions to client for coordinate mapping.
                let config = ConfigUpdate(
                    screenWidth: capture.displayWidth,
                    screenHeight: capture.displayHeight,
                    fps: fps
                )
                client.sendJSON(.configUpdate, payload: config)

                Log.capture.info("Video pipeline started: \(scaledWidth)x\(scaledHeight) @ \(fps)fps, \(bitrate/1000)kbps")
            } catch {
                Log.capture.error("Failed to start video pipeline: \(error.localizedDescription)")
            }
        }
    }

    private func stopVideoPipeline() {
        captureManager?.onPixelBuffer = nil
        videoEncoder?.stop()
        Task {
            await captureManager?.stopCapture()
        }
        videoEncoder = nil
        captureManager = nil
        Log.capture.info("Video pipeline stopped")
    }
}
