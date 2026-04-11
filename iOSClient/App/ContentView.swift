import SwiftUI

/// Root view: NavigationStack driving the server discovery → auth → remote session flow.
struct ContentView: View {

    @StateObject private var browser = ServerBrowser()
    @StateObject private var connection = ClientConnection()

    @State private var selectedServer: DiscoveredServer?
    @State private var navigationPath = NavigationPath()
    @State private var pendingPassword: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ServerListView(browser: browser) { server in
                selectedServer = server
                navigationPath.append("password")
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "password":
                    passwordScreen
                case "session":
                    RemoteSessionView(connection: connection)
                        .navigationBarBackButtonHidden()
                default:
                    EmptyView()
                }
            }
        }
        .onChange(of: connection.state) { _, newState in
            switch newState {
            case .authenticating:
                // Connection is ready — send the pending auth request.
                if let password = pendingPassword {
                    connection.sendAuthRequest(password: password)
                    pendingPassword = nil
                }
            case .connected:
                navigationPath = NavigationPath()
                navigationPath.append("session")
            case .disconnected:
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }
            default:
                break
            }
        }
    }

    // MARK: - Password Screen

    @ViewBuilder
    private var passwordScreen: some View {
        if let server = selectedServer {
            switch connection.state {
            case .waitingForApproval:
                waitingForApprovalView(serverName: server.name)
            case .error(let message):
                errorView(message: message, server: server)
            default:
                PasswordEntryView(serverName: server.name) { password in
                    pendingPassword = password
                    connection.connect(to: server.endpoint)
                }
            }
        }
    }

    private func waitingForApprovalView(serverName: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Waiting for \(serverName) to approve...")
                .font(.headline)
            Text("Check your Mac for the approval dialog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Connecting")
    }

    private func errorView(message: String, server: DiscoveredServer) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                connection.disconnect()
                // Stay on password screen for retry.
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Error")
    }
}
