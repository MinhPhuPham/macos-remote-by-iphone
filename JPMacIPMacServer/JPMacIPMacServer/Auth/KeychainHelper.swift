import Foundation
import JPMacIPRemoteShared
import Security

/// Secure password storage and retrieval using the macOS Keychain.
final class KeychainHelper {

    private static let serviceName = AppConstants.keychainService
    private static let passwordAccount = "server-password"

    // MARK: - Password

    /// Store or update the server password in the Keychain.
    static func storePassword(_ password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  serviceName,
            kSecAttrAccount as String:  passwordAccount,
        ]

        // Delete existing entry first.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Retrieve the stored server password from the Keychain.
    static func retrievePassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  serviceName,
            kSecAttrAccount as String:  passwordAccount,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete the stored password.
    static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  serviceName,
            kSecAttrAccount as String:  passwordAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - PIN Generation

    /// Generate a random 6-digit PIN.
    static func generatePIN() -> String {
        let pin = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        return pin
    }

    // MARK: - Session Token

    /// Generate a cryptographically random session token (256-bit).
    static func generateSessionToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: MyRemoteConstants.sessionTokenLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.randomGenerationFailed(status: status)
        }
        return Data(bytes).base64EncodedString()
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case unhandledError(status: OSStatus)
    case encodingFailed
    case randomGenerationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledError(let status):
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode password as UTF-8"
        case .randomGenerationFailed(let status):
            return "Secure random generation failed: \(status)"
        }
    }
}
