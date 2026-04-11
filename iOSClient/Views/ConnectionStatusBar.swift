import SwiftUI

/// Overlay bar showing connection status, FPS, and latency.
struct ConnectionStatusBar: View {

    let fps: Int
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
            }

            Divider()
                .frame(height: 12)

            Text("\(fps) FPS")
                .font(.caption2.monospacedDigit())

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(isConnected ? "connected" : "disconnected"), \(fps) frames per second")
    }
}
