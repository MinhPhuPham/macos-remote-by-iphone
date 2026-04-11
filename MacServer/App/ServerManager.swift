import Foundation
import AppKit
import Network

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

    /// Icon name for the menu bar.
    var statusIcon: String {
        if connectedClient != nil { return "circle.fill" }
        if isRunning { return "circle.dotted" }
        return "circle"
    }

    // MARK: - Dependencies

    let authManager: AuthManager
    let trustedDeviceStore: TrustedDeviceStore
    private let advertiser: BonjourAdvertiser

    // Called by capture/input modules when they need references.
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
        // Ensure a password is set.
        if authManager.currentPassword() == nil {
            let pin = try? authManager.generatePIN()
            print("[Server] Generated initial PIN: \(pin ?? "error")")
        }
        // TODO: Generate TLS identity from Keychain in production.
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
        // Reject if already connected.
        if authManager.hasActiveSession {
            nwConnection.cancel()
            return
        }

        let client = ServerConnection(connection: nwConnection)

        client.onFrameReceived = { [weak self] frame, conn in
            self?.handleFrame(frame, from: conn)
        }

        client.onDisconnected = { [weak self] _ in
            DispatchQueue.main.async {
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
        case .mouseEvent, .keyEvent, .scrollEvent:
            // Forward to input injectors (wired up externally).
            onClientAuthenticated != nil ? handleInputFrame(frame) : ()
        case .keyframeRequest:
            // Handled by capture manager (wired up externally).
            break
        case .heartbeat:
            break
        case .disconnect:
            DispatchQueue.main.async { self.handleClientDisconnected() }
        default:
            break
        }
    }

    private func handleInputFrame(_ frame: ProtocolFrame) {
        // Validate session token in the payload.
        // Input frames are handled externally via onClientAuthenticated callbacks.
    }

    // MARK: - Auth Flow

    private func handleAuthRequest(_ frame: ProtocolFrame, from client: ServerConnection) {
        guard let request = try? MessageCodec.decodePayload(AuthRequest.self, from: frame) else {
            let result = AuthResult(success: false, reason: "Invalid request format")
            client.sendJSON(.authResult, payload: result)
            return
        }

        let clientIP = client.clientIP

        // Check brute force block.
        if authManager.isBlocked(ip: clientIP) {
            let result = AuthResult(success: false, reason: "Too many attempts. Try again later.")
            client.sendJSON(.authResult, payload: result)
            return
        }

        // Validate password.
        guard authManager.validatePassword(request.password) else {
            authManager.recordFailedAttempt(ip: clientIP)
            let result = AuthResult(success: false, reason: "Invalid password")
            client.sendJSON(.authResult, payload: result)
            return
        }

        authManager.clearFailedAttempts(ip: clientIP)

        // Check if device is trusted (skip dialog).
        if authManager.deviceIsTrusted(request.deviceUUID) {
            grantAccess(to: client, deviceName: request.deviceName)
            return
        }

        // Show confirmation dialog on main thread.
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
        let alert = NSAlert()
        alert.messageText = "\"\(deviceName)\" (\(clientIP)) wants to connect."
        alert.informativeText = "This device will be able to see your screen and control your mouse and keyboard."
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Deny")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Allow Once
            grantAccess(to: client, deviceName: deviceName)

        case .alertSecondButtonReturn:
            // Always Allow — save to trusted devices.
            trustedDeviceStore.trust(deviceUUID: deviceUUID, deviceName: deviceName)
            grantAccess(to: client, deviceName: deviceName)

        default:
            // Deny
            let result = AuthResult(success: false, reason: "Connection denied by user")
            client.sendJSON(.authResult, payload: result)
            client.disconnect()
        }
    }

    private func grantAccess(to client: ServerConnection, deviceName: String) {
        let token = authManager.createSession(deviceName: deviceName)
        let result = AuthResult(success: true, sessionToken: token)
        client.sendJSON(.authResult, payload: result)

        DispatchQueue.main.async {
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
