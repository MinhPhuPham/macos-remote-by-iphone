import Foundation

/// Authorization level chosen by the user in the confirmation dialog.
enum AuthorizationLevel {
    case deny
    case allowOnce
    case alwaysAllow
}

/// Manages server-side authentication: password validation, brute-force protection,
/// session tokens, and the user confirmation flow.
final class AuthManager: ObservableObject {

    @Published private(set) var currentSessionToken: String?
    @Published private(set) var connectedDeviceName: String?

    private let trustedDeviceStore: TrustedDeviceStore

    /// Tracks failed attempts per IP for brute-force protection.
    private var failedAttempts: [String: (count: Int, lastAttempt: Date)] = [:]

    init(trustedDeviceStore: TrustedDeviceStore) {
        self.trustedDeviceStore = trustedDeviceStore
    }

    // MARK: - Password Management

    /// Set or update the server password.
    func setPassword(_ password: String) throws {
        try KeychainHelper.storePassword(password)
    }

    /// Generate a random 6-digit PIN and store it as the password.
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

    /// Check if an IP address is currently blocked.
    func isBlocked(ip: String) -> Bool {
        guard let record = failedAttempts[ip] else { return false }
        if record.count >= MyRemoteConstants.maxFailedAuthAttempts {
            let elapsed = Date().timeIntervalSince(record.lastAttempt)
            if elapsed < MyRemoteConstants.authBlockDuration {
                return true
            } else {
                // Block expired, reset.
                failedAttempts.removeValue(forKey: ip)
                return false
            }
        }
        return false
    }

    /// Record a failed authentication attempt from an IP.
    func recordFailedAttempt(ip: String) {
        var record = failedAttempts[ip] ?? (count: 0, lastAttempt: Date())
        record.count += 1
        record.lastAttempt = Date()
        failedAttempts[ip] = record
    }

    /// Clear failed attempts for an IP (e.g., on successful auth).
    func clearFailedAttempts(ip: String) {
        failedAttempts.removeValue(forKey: ip)
    }

    // MARK: - Password Validation

    /// Validate the supplied password against the stored one.
    func validatePassword(_ password: String) -> Bool {
        guard let stored = KeychainHelper.retrievePassword() else { return false }
        return password == stored
    }

    // MARK: - Session Management

    /// Create a new session after successful auth.
    func createSession(deviceName: String) -> String {
        let token = KeychainHelper.generateSessionToken()
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
