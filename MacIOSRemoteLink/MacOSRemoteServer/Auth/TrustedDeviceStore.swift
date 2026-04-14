import Combine
import Foundation

/// Represents a trusted iOS client device.
struct TrustedDevice: Identifiable, Codable, Hashable {
    let id: String          // device UUID
    let name: String        // user-set device name (e.g., "John's iPhone")
    let model: String       // device model (e.g., "iPhone")
    let dateAdded: Date

    /// For backward compatibility with stored data that may not have `model`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "iPhone"
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
    }

    init(id: String, name: String, model: String, dateAdded: Date) {
        self.id = id
        self.name = name
        self.model = model
        self.dateAdded = dateAdded
    }
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

    func trust(deviceUUID: String, deviceName: String, deviceModel: String = "iPhone") {
        // Update existing device info if already trusted.
        if let idx = devices.firstIndex(where: { $0.id == deviceUUID }) {
            devices[idx] = TrustedDevice(id: deviceUUID, name: deviceName,
                                         model: deviceModel, dateAdded: devices[idx].dateAdded)
        } else {
            devices.append(TrustedDevice(id: deviceUUID, name: deviceName,
                                         model: deviceModel, dateAdded: Date()))
        }
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
