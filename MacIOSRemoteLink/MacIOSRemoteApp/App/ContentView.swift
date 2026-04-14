import SwiftUI

/// Type-safe navigation routes.
enum Route: Hashable {
    case password
    case wanPassword(host: String, port: UInt16)
    case session
}

/// Connection tab selection.
enum ConnectionTab: String, CaseIterable, Identifiable {
    case local = "Same WiFi"
    case remote = "Remote IP"

    var id: String { rawValue }
}

/// Root view: NavigationStack with Local WiFi / Remote IP connection modes.
struct ContentView: View {

    @StateObject private var browser = ServerBrowser()
    @StateObject private var connection = ClientConnection()

    @State private var selectedServer: DiscoveredServer?
    @State private var navigationPath = NavigationPath()
    @State private var pendingPassword: String?
    @State private var connectionTab: ConnectionTab = .local

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                connectionModePicker

                switch connectionTab {
                case .local:
                    ServerListView(browser: browser) { server in
                        selectedServer = server
                        navigationPath.append(Route.password)
                    }
                case .remote:
                    ManualConnectionView { host, port in
                        navigationPath.append(Route.wanPassword(host: host, port: port))
                    }
                }
                
                Spacer(minLength: 0)
            }
            .navigationTitle("MyRemote")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .password:
                    passwordScreen(serverName: selectedServer?.name ?? "Mac")
                case .wanPassword(let host, let port):
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
            ForEach(ConnectionTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - LAN Password Screen

    @ViewBuilder
    private func passwordScreen(serverName: String) -> some View {
        connectionStateView(serverName: serverName) {
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
        connectionStateView(serverName: host) {
            PasswordEntryView(serverName: host) { password in
                pendingPassword = password
                connection.connect(host: host, port: port)
            }
        }
    }

    // MARK: - Connection State Wrapper

    @ViewBuilder
    private func connectionStateView<Content: View>(serverName: String, @ViewBuilder defaultContent: () -> Content) -> some View {
        switch connection.state {
        case .waitingForApproval:
            statusView(icon: nil, title: "Waiting for \(serverName) to approve...",
                       subtitle: "Check your Mac for the approval dialog.", showProgress: true)
                .navigationTitle("Connecting")
        case .reconnecting(let attempt):
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5)
                Text("Reconnecting...").font(.headline)
                Text("Attempt \(attempt) of \(MyRemoteConstants.maxReconnectRetries)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Cancel") { connection.disconnect() }.buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Reconnecting")
        case .error(let message):
            statusView(icon: "exclamationmark.triangle", title: message, iconColor: .red)
                .navigationTitle("Error")
        default:
            defaultContent()
        }
    }

    private func statusView(icon: String?, title: String, subtitle: String? = nil,
                            iconColor: Color = .secondary, showProgress: Bool = false) -> some View {
        VStack(spacing: 16) {
            if showProgress {
                ProgressView().scaleEffect(1.5)
            }
            if let icon {
                Image(systemName: icon).font(.system(size: 48)).foregroundStyle(iconColor)
            }
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if case .error = connection.state {
                Button("Try Again") { connection.disconnect() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
