import AppKit
import Combine
import Foundation
import JPMacIPRemoteShared
import Network
import os

private let logger = Logger(subsystem: "com.myremote.server", category: "ServerManager")

/// Central coordinator for the macOS server.
/// Manages networking, auth flow, client connections, and streaming state.
final class ServerManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Server stopped"
    @Published private(set) var connectedClient: ServerConnection?
    @Published var streamQuality: StreamQuality = .medium

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
    let pairingManager: PairingCodeManager
    private let advertiser: BonjourAdvertiser
    private let mouseInjector = MouseInjector()
    private let keyboardInjector = KeyboardInjector()

    var onClientAuthenticated: ((ServerConnection, String) -> Void)?
    var onClientDisconnected: (() -> Void)?

    // MARK: - Init

    init() {
        let store = TrustedDeviceStore()
        self.trustedDeviceStore = store
        self.authManager = AuthManager(trustedDeviceStore: store)
        self.advertiser = BonjourAdvertiser()
        self.pairingManager = PairingCodeManager()

        advertiser.onNewConnection = { [weak self] nwConnection in
            self?.handleIncomingConnection(nwConnection)
        }
    }

    // MARK: - Server Lifecycle

    func start() {
        if authManager.currentPassword() == nil {
            do {
                try authManager.generatePIN()
                logger.info("Generated initial PIN (check Settings to view)")
            } catch {
                logger.error("Failed to generate PIN: \(error.localizedDescription)")
            }
        }
        advertiser.start(tlsIdentity: nil)
        pairingManager.generateAndRegister()
        isRunning = true
        statusMessage = "Waiting for connections..."
    }

    func stop() {
        connectedClient?.disconnect()
        connectedClient = nil
        advertiser.stop()
        pairingManager.unregister()
        authManager.endSession()
        isRunning = false
        statusMessage = "Server stopped"
        onClientDisconnected?()
    }

    // MARK: - Incoming Connection

    private func handleIncomingConnection(_ nwConnection: NWConnection) {
        if authManager.hasActiveSession {
            nwConnection.cancel()
            return
        }

        let client = ServerConnection(connection: nwConnection)

        client.onFrameReceived = { [weak self] frame, conn in
            self?.handleFrame(frame, from: conn)
        }

        client.onDisconnected = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleClientDisconnected()
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
            break // Handled by capture manager (wired externally).
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
            break
        }
    }

    private func handleQualityUpdate(_ frame: ProtocolFrame) {
        guard let update = try? MessageCodec.decodePayload(QualityUpdate.self, from: frame) else { return }
        logger.info("Client requested quality: bitrate=\(update.requestedBitrate), fps=\(update.requestedFPS)")
        // Forward to capture/encoder (wired externally via onClientAuthenticated).
        // The encoder's setBitrate/setFrameRate methods are called here.
    }

    /// Validate session token before processing an input event.
    private func handleInputEvent(_ frame: ProtocolFrame, handler: (ProtocolFrame) -> Void) {
        // Extract session token from JSON payload for validation.
        struct TokenCheck: Decodable { let sessionToken: String }
        guard let check = try? MessageCodec.decodePayload(TokenCheck.self, from: frame),
              authManager.validateSession(check.sessionToken) else {
            logger.warning("Rejected input event with invalid session token")
            return
        }
        handler(frame)
    }

    private func handleMouseEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(MouseEvent.self, from: frame) else { return }
        // Validate coordinates.
        guard event.x.isFinite, event.y.isFinite, event.x >= 0, event.y >= 0 else { return }
        mouseInjector.inject(event: event)
    }

    private func handleKeyEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(KeyEvent.self, from: frame) else { return }
        keyboardInjector.inject(event: event)
    }

    private func handleScrollEvent(_ frame: ProtocolFrame) {
        guard let event = try? MessageCodec.decodePayload(ScrollEvent.self, from: frame) else { return }
        guard event.deltaX.isFinite, event.deltaY.isFinite else { return }
        mouseInjector.scroll(deltaX: Int32(event.deltaX), deltaY: Int32(event.deltaY))
    }

    // MARK: - Auth Flow

    private func handleAuthRequest(_ frame: ProtocolFrame, from client: ServerConnection) {
        guard let request = try? MessageCodec.decodePayload(AuthRequest.self, from: frame) else {
            let result = AuthResult(success: false, reason: "Invalid request format")
            client.sendJSON(.authResult, payload: result)
            return
        }

        let clientIP = client.clientIP
        let deviceUUID = request.deviceUUID

        // Dual rate limiting: check both IP and device UUID.
        let blockCheck = authManager.isBlocked(ip: clientIP, deviceUUID: deviceUUID)
        if blockCheck.blocked {
            let result = AuthResult(success: false, reason: blockCheck.reason ?? "Too many attempts.")
            client.sendJSON(.authResult, payload: result)
            return
        }

        guard authManager.validatePassword(request.password) else {
            authManager.recordFailedAttempt(ip: clientIP, deviceUUID: deviceUUID)
            let result = AuthResult(success: false, reason: "Invalid password")
            client.sendJSON(.authResult, payload: result)
            return
        }

        authManager.clearFailedAttempts(ip: clientIP, deviceUUID: deviceUUID)
        client.isAuthenticated = true

        if authManager.deviceIsTrusted(request.deviceUUID) {
            DispatchQueue.main.async { [weak self] in
                self?.grantAccess(to: client, deviceName: request.deviceName)
            }
            return
        }

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

        let alert = NSAlert()
        alert.messageText = "\"\(sanitizedName)\" (\(clientIP)) wants to connect."
        alert.informativeText = "This device will be able to see your screen and control your mouse and keyboard."
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Deny")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            grantAccess(to: client, deviceName: sanitizedName)
        case .alertSecondButtonReturn:
            trustedDeviceStore.trust(deviceUUID: deviceUUID, deviceName: sanitizedName)
            grantAccess(to: client, deviceName: sanitizedName)
        default:
            let result = AuthResult(success: false, reason: "Connection denied by user")
            client.sendJSON(.authResult, payload: result)
            client.disconnect()
        }
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

        connectedClient = client
        statusMessage = "Connected to \(deviceName)"
        onClientAuthenticated?(client, token)
    }

    private func handleClientDisconnected() {
        connectedClient = nil
        authManager.endSession()
        statusMessage = isRunning ? "Waiting for connections..." : "Server stopped"
        onClientDisconnected?()
    }
}
