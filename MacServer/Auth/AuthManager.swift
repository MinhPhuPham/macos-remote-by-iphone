import Foundation
import os

private let logger = Logger(subsystem: "com.myremote.server", category: "AuthManager")

/// Manages server-side authentication: password validation, brute-force protection,
/// session tokens, and the user confirmation flow.
final class AuthManager: ObservableObject {

    @Published private(set) var currentSessionToken: String?
    @Published private(set) var connectedDeviceName: String?

    private let trustedDeviceStore: TrustedDeviceStore

    // MARK: - Dual Rate Limiting (IP + device UUID)
    // IP-based is primary (attacker can't fake their IP).
    // UUID-based is secondary (stable across network transitions for legitimate users).

    private var failedByIP: [String: (count: Int, lastAttempt: Date)] = [:]
    private var failedByUUID: [String: (count: Int, lastAttempt: Date)] = [:]
    private var globalFailureCount = 0
    private var globalWindowStart = Date()
    private let lock = NSLock()

    /// When true, all new auth attempts are temporarily rejected (global lockout).
    private(set) var isGloballyLocked = false

    init(trustedDeviceStore: TrustedDeviceStore) {
        self.trustedDeviceStore = trustedDeviceStore
    }

    // MARK: - Password Management

    func setPassword(_ password: String) throws {
        try KeychainHelper.storePassword(password)
    }

    @discardableResult
    func generatePIN() throws -> String {
        let pin = KeychainHelper.generatePIN()
        try KeychainHelper.storePassword(pin)
        return pin
    }

    func currentPassword() -> String? {
        KeychainHelper.retrievePassword()
    }

    // MARK: - Brute Force Protection (Dual Key)

    /// Check if an auth attempt should be blocked.
    /// Checks: IP block, UUID block, and global lockout.
    func isBlocked(ip: String, deviceUUID: String) -> (blocked: Bool, reason: String?) {
        lock.lock()
        defer { lock.unlock() }

        // Check global lockout first.
        if isGloballyLocked {
            let elapsed = Date().timeIntervalSince(globalWindowStart)
            if elapsed < MyRemoteConstants.authBlockDuration {
                return (true, "Server temporarily locked. Try again later.")
            } else {
                isGloballyLocked = false
                globalFailureCount = 0
            }
        }

        // Check IP-based block (primary — can't fake).
        if let record = failedByIP[ip] {
            if record.count >= MyRemoteConstants.maxFailedAuthAttempts {
                let elapsed = Date().timeIntervalSince(record.lastAttempt)
                if elapsed < MyRemoteConstants.authBlockDuration {
                    return (true, "Too many attempts from your network. Try again in \(Int(MyRemoteConstants.authBlockDuration - elapsed)) seconds.")
                } else {
                    failedByIP.removeValue(forKey: ip)
                }
            }
        }

        // Check UUID-based block (secondary — stable for legitimate users on cellular).
        if let record = failedByUUID[deviceUUID] {
            if record.count >= MyRemoteConstants.maxFailedAuthAttempts {
                let elapsed = Date().timeIntervalSince(record.lastAttempt)
                if elapsed < MyRemoteConstants.authBlockDuration {
                    return (true, "Too many attempts from this device. Try again later.")
                } else {
                    failedByUUID.removeValue(forKey: deviceUUID)
                }
            }
        }

        return (false, nil)
    }

    /// Record a failed authentication attempt.
    func recordFailedAttempt(ip: String, deviceUUID: String) {
        lock.lock()
        defer { lock.unlock() }

        // Increment IP counter.
        var ipRecord = failedByIP[ip] ?? (count: 0, lastAttempt: Date())
        ipRecord.count += 1
        ipRecord.lastAttempt = Date()
        failedByIP[ip] = ipRecord

        // Increment UUID counter.
        var uuidRecord = failedByUUID[deviceUUID] ?? (count: 0, lastAttempt: Date())
        uuidRecord.count += 1
        uuidRecord.lastAttempt = Date()
        failedByUUID[deviceUUID] = uuidRecord

        // Global counter — lock if too many failures from any source.
        let now = Date()
        if now.timeIntervalSince(globalWindowStart) > 600 {
            // Reset window every 10 minutes.
            globalFailureCount = 0
            globalWindowStart = now
        }
        globalFailureCount += 1
        if globalFailureCount >= 20 {
            isGloballyLocked = true
            logger.warning("Global auth lockout triggered: \(self.globalFailureCount) failures in window")
        }

        logger.info("Failed auth: IP=\(ip) UUID=\(deviceUUID) IP_count=\(ipRecord.count) UUID_count=\(uuidRecord.count) global=\(self.globalFailureCount)")
    }

    /// Clear failed attempts for a successful auth.
    func clearFailedAttempts(ip: String, deviceUUID: String) {
        lock.lock()
        defer { lock.unlock() }
        failedByIP.removeValue(forKey: ip)
        failedByUUID.removeValue(forKey: deviceUUID)
    }

    // MARK: - Password Validation (constant-time)

    /// Validate the supplied password using constant-time comparison.
    func validatePassword(_ password: String) -> Bool {
        guard let stored = KeychainHelper.retrievePassword() else { return false }
        return constantTimeEqual(password, stored)
    }

    /// Constant-time string comparison to prevent timing attacks.
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        // Always compare the full length of the longer string.
        let maxLen = max(aBytes.count, bBytes.count)
        guard maxLen > 0 else { return aBytes.count == bBytes.count }

        var result: UInt8 = 0
        // XOR length difference to detect mismatched lengths.
        result |= UInt8(truncatingIfNeeded: aBytes.count ^ bBytes.count)
        for i in 0..<maxLen {
            let aByte = i < aBytes.count ? aBytes[i] : 0
            let bByte = i < bBytes.count ? bBytes[i] : 0
            result |= aByte ^ bByte
        }
        return result == 0
    }

    // MARK: - Session Management

    func createSession(deviceName: String) -> String? {
        guard let token = try? KeychainHelper.generateSessionToken() else {
            logger.error("Failed to generate session token")
            return nil
        }
        currentSessionToken = token
        connectedDeviceName = deviceName
        return token
    }

    func validateSession(_ token: String) -> Bool {
        guard let current = currentSessionToken else { return false }
        return constantTimeEqual(token, current)
    }

    func endSession() {
        currentSessionToken = nil
        connectedDeviceName = nil
    }

    var hasActiveSession: Bool {
        currentSessionToken != nil
    }

    // MARK: - Trusted Device Check

    func deviceIsTrusted(_ deviceUUID: String) -> Bool {
        trustedDeviceStore.isTrusted(deviceUUID)
    }
}
