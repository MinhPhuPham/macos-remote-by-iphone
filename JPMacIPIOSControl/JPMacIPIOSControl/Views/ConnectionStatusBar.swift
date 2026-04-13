import JPMacIPRemoteShared
import SwiftUI

/// Overlay bar showing connection status, FPS, RTT, and network quality.
struct ConnectionStatusBar: View {

    let fps: Int
    let isConnected: Bool
    let rtt: Double
    let qualityLevel: NetworkQualityMonitor.QualityLevel
    let connectionMode: ConnectionMode

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
            }

            Divider()
                .frame(height: 12)

            Text("\(fps) FPS")
                .font(.caption2.monospacedDigit())

            if rtt > 0 {
                Divider()
                    .frame(height: 12)

                Text("\(Int(rtt))ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(rttColor)
            }

            Divider()
                .frame(height: 12)

            HStack(spacing: 2) {
                Image(systemName: connectionMode == .wan ? "globe" : "wifi")
                    .font(.caption2)
                qualityIndicator
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection: \(isConnected ? "connected" : "disconnected"), \(fps) frames per second, \(Int(rtt)) milliseconds latency, quality \(qualityLevel.rawValue)")
    }

    private var rttColor: Color {
        switch qualityLevel {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private var qualityIndicator: some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: i))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        switch qualityLevel {
        case .good: return .green
        case .fair: return index < 2 ? .yellow : .gray.opacity(0.3)
        case .poor: return index < 1 ? .red : .gray.opacity(0.3)
        }
    }
}
