import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Generates and persists a unique device UUID for this iOS client.
/// The UUID is stored securely in the Keychain (not UserDefaults).
enum DeviceIdentity {

    private static let service = AppConstants.keychainService
    private static let uuidAccount = "device-uuid"

    /// The persistent device UUID. Generated once on first access, stored in Keychain.
    static var uuid: String {
        if let existing = readFromKeychain() {
            return existing
        }
        let newUUID = UUID().uuidString
        saveToKeychain(newUUID)
        return newUUID
    }

    /// A human-readable device name.
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iOS Client"
        #endif
    }

    // MARK: - Keychain

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  uuidAccount,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToKeychain(_ uuid: String) {
        guard let data = uuid.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  uuidAccount,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary) // Remove existing.
        SecItemAdd(query as CFDictionary, nil)
    }
}
