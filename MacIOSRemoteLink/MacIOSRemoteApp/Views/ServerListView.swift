import SwiftUI

/// Displays discovered MyRemote servers on the local network.
struct ServerListView: View {

    @ObservedObject var browser: ServerBrowser
    let onSelectServer: (DiscoveredServer) -> Void

    var body: some View {
        Group {
            if browser.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .onAppear { browser.startBrowsing() }
        .onDisappear { browser.stopBrowsing() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching for Mac...")
                .font(.headline)

            Text("Make sure MyRemote Server is running on your Mac\nand both devices are on the same WiFi network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    /// Build display names with suffix for duplicates: "My Mac", "My Mac (2)", etc.
    private var displayNames: [String: String] {
        var nameCounts: [String: Int] = [:]
        var result: [String: String] = [:]

        // Count occurrences of each name.
        for server in browser.servers {
            nameCounts[server.name, default: 0] += 1
        }

        // Assign display names with suffix for duplicates.
        var nameIndex: [String: Int] = [:]
        for server in browser.servers {
            if nameCounts[server.name, default: 1] > 1 {
                let idx = nameIndex[server.name, default: 0]
                nameIndex[server.name] = idx + 1
                result[server.id] = "\(server.name) (\(idx + 1))"
            } else {
                result[server.id] = server.name
            }
        }
        return result
    }

    private var serverList: some View {
        let names = displayNames  // Compute once, not per row.
        return List(browser.servers) { server in
            Button {
                onSelectServer(server)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(names[server.id] ?? server.name)
                            .font(.headline)
                        Text("Available")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .refreshable {
            browser.stopBrowsing()
            browser.startBrowsing()
        }
    }
}
