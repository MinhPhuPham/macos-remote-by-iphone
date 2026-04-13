import Combine
import Foundation

/// Represents a trusted iOS client device.
struct TrustedDevice: Identifiable, Codable, Hashable {
    let id: String          // device UUID
    let name: String        // device display name
    let dateAdded: Date
}

/// Persists the list of trusted device UUIDs so they skip the confirmation dialog.
final class TrustedDeviceStore: ObservableObject {

    @Published private(set) var devices: [TrustedDevice] = []

    private static let storageKey = "MyRemote.TrustedDevices"

    init() {
        load()
    }

    // MARK: - Public API

    func isTrusted(_ deviceUUID: String) -> Bool {
        devices.contains { $0.id == deviceUUID }
    }

    func trust(deviceUUID: String, deviceName: String) {
        guard !isTrusted(deviceUUID) else { return }
        let device = TrustedDevice(id: deviceUUID, name: deviceName, dateAdded: Date())
        devices.append(device)
        save()
    }

    func revoke(deviceUUID: String) {
        devices.removeAll { $0.id == deviceUUID }
        save()
    }

    func revokeAll() {
        devices.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([TrustedDevice].self, from: data) else {
            return
        }
        devices = decoded
    }
}
