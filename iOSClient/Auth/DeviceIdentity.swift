import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Generates and persists a unique device UUID for this iOS client.
/// The UUID is stable across app launches (stored in UserDefaults).
enum DeviceIdentity {

    private static let uuidKey = "MyRemote.DeviceUUID"

    /// The persistent device UUID. Generated once on first access.
    static var uuid: String {
        if let existing = UserDefaults.standard.string(forKey: uuidKey) {
            return existing
        }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: uuidKey)
        return newUUID
    }

    /// A human-readable device name (e.g., "John's iPhone").
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iOS Client"
        #endif
    }

    /// Reset the device UUID (e.g., for testing).
    /// Warning: The server will treat this as a new device.
    static func resetUUID() {
        UserDefaults.standard.removeObject(forKey: uuidKey)
    }
}
