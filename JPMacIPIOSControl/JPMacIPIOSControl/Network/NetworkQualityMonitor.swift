import Combine
import Foundation
import JPMacIPRemoteShared
import os

/// Measures RTT via ping/pong and drives adaptive bitrate/FPS decisions.
/// Sends periodic pings to the server, measures round-trip time,
/// and recommends quality adjustments based on the connection mode.
final class NetworkQualityMonitor: ObservableObject {

    @Published private(set) var currentRTT: Double = 0        // ms
    @Published private(set) var averageRTT: Double = 0         // ms
    @Published private(set) var recommendedBitrate: Int = 0
    @Published private(set) var recommendedFPS: Int = 0
    @Published private(set) var qualityLevel: QualityLevel = .good

    enum QualityLevel: String, Sendable {
        case good     // Low RTT, full quality
        case fair     // Medium RTT, reduced quality
        case poor     // High RTT, minimum quality
    }

    private var mode: ConnectionMode
    private var rttSamples: [Double] = []
    private let maxSamples = 10
    private var pingTimer: DispatchSourceTimer?
    private var pendingPingTimestamp: UInt64?

    /// Called to send a ping frame over the connection.
    var sendPing: (() -> Void)?
    /// Called when quality should be updated on the server.
    var onQualityChange: ((Int, Int) -> Void)?  // (bitrate, fps)

    init(mode: ConnectionMode = .lan) {
        self.mode = mode
        self.recommendedBitrate = mode.defaultBitrate
        self.recommendedFPS = mode.defaultFrameRate
    }

    // MARK: - Mode

    func setMode(_ newMode: ConnectionMode) {
        mode = newMode
        rttSamples.removeAll()
        recommendedBitrate = newMode.defaultBitrate
        recommendedFPS = newMode.defaultFrameRate
        qualityLevel = .good
    }

    // MARK: - Ping/Pong Cycle

    func startMonitoring() {
        let interval = mode.heartbeatInterval
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendPingMessage()
        }
        timer.resume()
        pingTimer = timer
    }

    func stopMonitoring() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sendPingMessage() {
        let ping = PingPayload()
        pendingPingTimestamp = ping.timestamp
        sendPing?()
    }

    /// Call when a pong is received from the server.
    func receivedPong(payload: PingPayload) {
        guard let sentTime = pendingPingTimestamp, sentTime == payload.timestamp else { return }
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        let rtt = Double(now - sentTime)
        pendingPingTimestamp = nil

        rttSamples.append(rtt)
        if rttSamples.count > maxSamples {
            rttSamples.removeFirst()
        }

        let avg = rttSamples.reduce(0, +) / Double(rttSamples.count)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentRTT = rtt
            self.averageRTT = avg
            self.evaluateQuality(averageRTT: avg)
        }
    }

    // MARK: - Adaptive Quality

    private func evaluateQuality(averageRTT: Double) {
        let oldBitrate = recommendedBitrate
        let oldFPS = recommendedFPS

        if averageRTT > mode.highRTTThreshold {
            // Poor connection — drop to minimum quality.
            recommendedBitrate = mode.lowBitrate
            recommendedFPS = mode.lowFrameRate
            qualityLevel = .poor
        } else if averageRTT > mode.lowRTTThreshold {
            // Fair connection — use default quality.
            recommendedBitrate = mode.defaultBitrate
            recommendedFPS = mode.defaultFrameRate
            qualityLevel = .fair
        } else {
            // Good connection — use highest quality for this mode.
            recommendedBitrate = mode.highBitrate
            recommendedFPS = mode.defaultFrameRate
            qualityLevel = .good
        }

        if recommendedBitrate != oldBitrate || recommendedFPS != oldFPS {
            Log.quality.info("Quality change: \(self.qualityLevel.rawValue) — bitrate=\(self.recommendedBitrate), fps=\(self.recommendedFPS), RTT=\(Int(averageRTT))ms")
            onQualityChange?(recommendedBitrate, recommendedFPS)
        }
    }
}
