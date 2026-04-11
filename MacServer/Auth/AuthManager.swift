import Foundation
import os

private let logger = Logger(subsystem: "com.myremote.server", category: "AuthManager")

/// Manages server-side authentication: password validation, brute-force protection,
/// session tokens, and the user confirmation flow.
final class AuthManager: ObservableObject {

    @Published private(set) var currentSessionToken: String?
    @Published private(set) var connectedDeviceName: String?

    private let trustedDeviceStore: TrustedDeviceStore

    /// Tracks failed attempts per device UUID (not IP, which changes on cellular).
    /// Protected by `lock` for thread safety — accessed from network callbacks.
    private var failedAttempts: [String: (count: Int, lastAttempt: Date)] = [:]
    private let lock = NSLock()

    init(trustedDeviceStore: TrustedDeviceStore) {
        self.trustedDeviceStore = trustedDeviceStore
    }

    // MARK: - Password Management

    /// Set or update the server password.
    func setPassword(_ password: String) throws {
        try KeychainHelper.storePassword(password)
    }

    /// Generate a random 6-digit PIN and store it as the password.
    @discardableResult
    func generatePIN() throws -> String {
        let pin = KeychainHelper.generatePIN()
        try KeychainHelper.storePassword(pin)
        return pin
    }

    /// Retrieve the current password/PIN (for display in settings).
    func currentPassword() -> String? {
        KeychainHelper.retrievePassword()
    }

    // MARK: - Brute Force Protection

    /// Check if a device UUID is currently blocked.
    func isBlocked(deviceUUID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let record = failedAttempts[deviceUUID] else { return false }
        if record.count >= MyRemoteConstants.maxFailedAuthAttempts {
            let elapsed = Date().timeIntervalSince(record.lastAttempt)
            if elapsed < MyRemoteConstants.authBlockDuration {
                return true
            } else {
                failedAttempts.removeValue(forKey: deviceUUID)
                return false
            }
        }
        return false
    }

    /// Record a failed authentication attempt from a device.
    func recordFailedAttempt(deviceUUID: String) {
        lock.lock()
        defer { lock.unlock() }
        var record = failedAttempts[deviceUUID] ?? (count: 0, lastAttempt: Date())
        record.count += 1
        record.lastAttempt = Date()
        failedAttempts[deviceUUID] = record
    }

    /// Clear failed attempts for a device (e.g., on successful auth).
    func clearFailedAttempts(deviceUUID: String) {
        lock.lock()
        defer { lock.unlock() }
        failedAttempts.removeValue(forKey: deviceUUID)
    }

    // MARK: - Password Validation

    /// Validate the supplied password against the stored one.
    func validatePassword(_ password: String) -> Bool {
        guard let stored = KeychainHelper.retrievePassword() else { return false }
        return password == stored
    }

    // MARK: - Session Management

    /// Create a new session after successful auth.
    func createSession(deviceName: String) -> String? {
        guard let token = try? KeychainHelper.generateSessionToken() else {
            logger.error("Failed to generate session token")
            return nil
        }
        currentSessionToken = token
        connectedDeviceName = deviceName
        return token
    }

    /// Validate that a session token matches the active session.
    func validateSession(_ token: String) -> Bool {
        guard let current = currentSessionToken else { return false }
        return token == current
    }

    /// End the current session.
    func endSession() {
        currentSessionToken = nil
        connectedDeviceName = nil
    }

    /// Whether a client is currently connected.
    var hasActiveSession: Bool {
        currentSessionToken != nil
    }

    // MARK: - Trusted Device Check

    /// Check whether the device requires user confirmation.
    /// Returns true if the device is trusted (no dialog needed).
    func deviceIsTrusted(_ deviceUUID: String) -> Bool {
        trustedDeviceStore.isTrusted(deviceUUID)
    }
}
