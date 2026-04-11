import SwiftUI

/// Type-safe navigation routes.
enum Route: Hashable {
    case password
    case manualPassword(host: String, port: UInt16)
    case session
}

/// Root view: NavigationStack with LAN/WAN connection modes.
struct ContentView: View {

    @StateObject private var browser = ServerBrowser()
    @StateObject private var connection = ClientConnection()

    @State private var selectedServer: DiscoveredServer?
    @State private var navigationPath = NavigationPath()
    @State private var pendingPassword: String?
    @State private var connectionTab: ConnectionMode = .lan

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                connectionModePicker

                switch connectionTab {
                case .lan:
                    ServerListView(browser: browser) { server in
                        selectedServer = server
                        navigationPath.append(Route.password)
                    }
                case .wan:
                    ManualConnectionView { host, port in
                        navigationPath.append(Route.manualPassword(host: host, port: port))
                    }
                }
            }
            .navigationTitle("MyRemote")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .password:
                    passwordScreen(serverName: selectedServer?.name ?? "Mac")
                case .manualPassword(let host, let port):
                    wanPasswordScreen(host: host, port: port)
                case .session:
                    RemoteSessionView(connection: connection)
                        .navigationBarBackButtonHidden()
                }
            }
        }
        .onChange(of: connection.state) { _, newState in
            switch newState {
            case .authenticating:
                if let password = pendingPassword {
                    connection.sendAuthRequest(password: password)
                    pendingPassword = nil
                }
            case .connected:
                navigationPath = NavigationPath()
                navigationPath.append(Route.session)
            case .disconnected:
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }
            default:
                break
            }
        }
    }

    // MARK: - Connection Mode Picker

    private var connectionModePicker: some View {
        Picker("Connection Mode", selection: $connectionTab) {
            Label("Local WiFi", systemImage: "wifi").tag(ConnectionMode.lan)
            Label("Internet", systemImage: "globe").tag(ConnectionMode.wan)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityLabel("Connection mode: \(connectionTab.rawValue)")
    }

    // MARK: - LAN Password Screen

    @ViewBuilder
    private func passwordScreen(serverName: String) -> some View {
        switch connection.state {
        case .waitingForApproval:
            waitingView(serverName: serverName)
        case .reconnecting(let attempt):
            reconnectingView(attempt: attempt)
        case .error(let message):
            errorView(message: message)
        default:
            PasswordEntryView(serverName: serverName) { password in
                guard let server = selectedServer else { return }
                pendingPassword = password
                connection.connect(to: server.endpoint)
            }
        }
    }

    // MARK: - WAN Password Screen

    @ViewBuilder
    private func wanPasswordScreen(host: String, port: UInt16) -> some View {
        switch connection.state {
        case .waitingForApproval:
            waitingView(serverName: host)
        case .reconnecting(let attempt):
            reconnectingView(attempt: attempt)
        case .error(let message):
            errorView(message: message)
        default:
            PasswordEntryView(serverName: host) { password in
                pendingPassword = password
                connection.connect(host: host, port: port)
            }
        }
    }

    // MARK: - Status Views

    private func waitingView(serverName: String) -> some View {
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

    private func reconnectingView(attempt: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Reconnecting...")
                .font(.headline)
            Text("Attempt \(attempt) of \(MyRemoteConstants.maxReconnectRetries)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                connection.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Reconnecting")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                connection.disconnect()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Error")
    }
}
