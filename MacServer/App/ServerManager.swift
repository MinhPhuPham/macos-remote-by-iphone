import Foundation
import AppKit
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

        var bitrate: Int {
            switch self {
            case .low:    return MyRemoteConstants.lowBitrate
            case .medium: return MyRemoteConstants.defaultBitrate
            case .high:   return MyRemoteConstants.highBitrate
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

    var onClientAuthenticated: ((ServerConnection, String) -> Void)?
    var onClientDisconnected: (() -> Void)?

    // MARK: - Init

    init() {
        let store = TrustedDeviceStore()
        self.trustedDeviceStore = store
        self.authManager = AuthManager(trustedDeviceStore: store)
        self.advertiser = BonjourAdvertiser()

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
        isRunning = true
        statusMessage = "Waiting for connections..."
    }

    func stop() {
        connectedClient?.disconnect()
        connectedClient = nil
        advertiser.stop()
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
        case .disconnect:
            DispatchQueue.main.async { [weak self] in self?.handleClientDisconnected() }
        default:
            break
        }
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

        if authManager.isBlocked(ip: clientIP) {
            let result = AuthResult(success: false, reason: "Too many attempts. Try again later.")
            client.sendJSON(.authResult, payload: result)
            return
        }

        guard authManager.validatePassword(request.password) else {
            authManager.recordFailedAttempt(ip: clientIP)
            let result = AuthResult(success: false, reason: "Invalid password")
            client.sendJSON(.authResult, payload: result)
            return
        }

        authManager.clearFailedAttempts(ip: clientIP)

        if authManager.deviceIsTrusted(request.deviceUUID) {
            grantAccess(to: client, deviceName: request.deviceName)
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

    private func grantAccess(to client: ServerConnection, deviceName: String) {
        guard let token = authManager.createSession(deviceName: deviceName) else {
            let result = AuthResult(success: false, reason: "Internal server error")
            client.sendJSON(.authResult, payload: result)
            return
        }

        let result = AuthResult(success: true, sessionToken: token)
        client.sendJSON(.authResult, payload: result)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedClient = client
            self.statusMessage = "Connected to \(deviceName)"
            self.onClientAuthenticated?(client, token)
        }
    }

    private func handleClientDisconnected() {
        connectedClient = nil
        authManager.endSession()
        statusMessage = isRunning ? "Waiting for connections..." : "Server stopped"
        onClientDisconnected?()
    }
}
