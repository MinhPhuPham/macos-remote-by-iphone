import Combine
import Foundation
import Network
import os

/// Discovered server info.
struct DiscoveredServer: Identifiable, Hashable {
    let id: String          // Unique endpoint description
    let name: String        // Bonjour service name
    let endpoint: NWEndpoint

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.id == rhs.id
    }
}

/// Discovers MyRemote servers on the local network via Bonjour.
final class ServerBrowser: ObservableObject {

    @Published private(set) var servers: [DiscoveredServer] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?

    // MARK: - Start / Stop

    func startBrowsing() {
        Log.connection.debug("Starting Bonjour browser for \(MyRemoteConstants.bonjourServiceType)")
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: MyRemoteConstants.bonjourServiceType,
            domain: nil
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    Log.connection.debug("Browser ready")
                    self?.isSearching = true
                case .failed:
                    Log.connection.warning("Browser failed")
                    self?.isSearching = false
                case .cancelled:
                    Log.connection.debug("Browser cancelled")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Log.connection.debug("Found \(results.count) servers")
            DispatchQueue.main.async {
                self?.servers = results.compactMap { result in
                    let name: String
                    if case let .service(serviceName, _, _, _) = result.endpoint {
                        name = serviceName
                    } else {
                        name = "Unknown Server"
                    }
                    return DiscoveredServer(
                        id: "\(result.endpoint)",
                        name: name,
                        endpoint: result.endpoint
                    )
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        Log.connection.debug("Browser stopped")
        browser?.cancel()
        browser = nil
        isSearching = false
        servers = []
    }
}
