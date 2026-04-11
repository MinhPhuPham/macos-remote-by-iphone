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
        .navigationTitle("MyRemote")
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

    private var serverList: some View {
        List(browser.servers) { server in
            Button {
                onSelectServer(server)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
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
            .accessibilityLabel("\(server.name), available")
            .accessibilityHint("Double tap to connect")
        }
    }
}
