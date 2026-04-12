import SwiftUI
import CoreMedia
import os

private let logger = Logger(subsystem: "com.myremote.client", category: "RemoteSession")

// MARK: - Session Pipeline Coordinator

/// Owns the video pipeline and gesture handler as a single `ObservableObject`.
/// Using `@StateObject` ensures stable identity across SwiftUI view updates.
final class SessionPipeline: ObservableObject {

    var displayView: VideoDisplayUIView?
    let videoDecoder = VideoDecoder()
    let gestureHandler = GestureHandler()
    let sampleBufferFactory = SampleBufferFactory()

    @Published private(set) var fps: Int = 0
    private var frameCount: Int = 0
    private var lastFPSUpdate = Date()

    func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            let newFPS = frameCount
            frameCount = 0
            lastFPSUpdate = now
            // Only publish when value changes to avoid unnecessary SwiftUI diffs.
            if newFPS != fps {
                fps = newFPS
            }
        }
    }

    func reset() {
        videoDecoder.invalidate()
        frameCount = 0
        fps = 0
    }
}

// MARK: - Remote Session View

/// Full-screen remote session view: video display + gesture input + toolbar.
struct RemoteSessionView: View {

    @ObservedObject var connection: ClientConnection
    @StateObject private var pipeline = SessionPipeline()

    @State private var activeModifiers = ModifierKeys()
    @State private var isKeyboardActive = false
    @State private var showStatusBar = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            overlayControls
        }
        .onAppear { startVideoReceiver() }
        .onDisappear { cleanup() }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remote desktop session")
    }

    // MARK: - Subviews

    private var videoLayer: some View {
        VideoDisplayView { createdView in
            pipeline.displayView = createdView
            setupGestures(on: createdView)
        }
        .ignoresSafeArea()
    }

    private var overlayControls: some View {
        VStack(spacing: 0) {
            if showStatusBar {
                ConnectionStatusBar(
                    fps: pipeline.fps,
                    isConnected: connection.state == .connected,
                    rtt: connection.qualityMonitor.averageRTT,
                    qualityLevel: connection.qualityMonitor.qualityLevel,
                    connectionMode: connection.connectionMode
                )
            }

            Spacer()

            if isKeyboardActive {
                VirtualKeyboardView(isActive: $isKeyboardActive) { char, keyCode, _ in
                    sendKeyEvent(keyCode: keyCode, character: char)
                }
                .frame(height: 1)
            }

            ModifierKeysBar(activeModifiers: $activeModifiers) {
                isKeyboardActive.toggle()
            }

            ToolbarView(
                isKeyboardActive: $isKeyboardActive,
                showStatusBar: $showStatusBar,
                onDisconnect: { connection.disconnect() }
            )
        }
    }

    // MARK: - Video Pipeline

    private func startVideoReceiver() {
        pipeline.videoDecoder.onDecodedFrame = { [weak pipeline] pixelBuffer, timestamp in
            guard let pipeline = pipeline else { return }
            if let sampleBuffer = pipeline.sampleBufferFactory.create(from: pixelBuffer, presentationTime: timestamp) {
                DispatchQueue.main.async { [weak pipeline] in
                    pipeline?.displayView?.enqueue(sampleBuffer)
                    pipeline?.updateFPS()
                }
            }
        }

        connection.onFrameReceived = { [weak pipeline] frame in
            guard let pipeline = pipeline else { return }
            switch frame.type {
            case .videoConfig:
                handleVideoConfig(frame, pipeline: pipeline)
            case .videoFrame:
                pipeline.videoDecoder.decode(nalData: frame.payload)
            case .configUpdate:
                handleConfigUpdate(frame, pipeline: pipeline)
            default:
                break
            }
        }
    }

    private func handleVideoConfig(_ frame: ProtocolFrame, pipeline: SessionPipeline) {
        let data = frame.payload
        guard data.count > 4 else { return }
        let spsLength = Int(data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard data.count >= 4 + spsLength else { return }

        let sps = data.subdata(in: 4..<(4 + spsLength))
        let pps = data.subdata(in: (4 + spsLength)..<data.count)

        do {
            try pipeline.videoDecoder.configure(sps: sps, pps: pps)
        } catch {
            logger.error("Failed to configure video decoder: \(error.localizedDescription)")
        }
    }

    private func handleConfigUpdate(_ frame: ProtocolFrame, pipeline: SessionPipeline) {
        guard let config = try? MessageCodec.decodePayload(ConfigUpdate.self, from: frame) else { return }
        // Dispatch to main thread — gestureHandler properties are read from main.
        DispatchQueue.main.async { [weak pipeline] in
            pipeline?.gestureHandler.serverScreenWidth = CGFloat(config.screenWidth)
            pipeline?.gestureHandler.serverScreenHeight = CGFloat(config.screenHeight)
        }
    }

    // MARK: - Gestures

    private func setupGestures(on view: VideoDisplayUIView) {
        pipeline.gestureHandler.onMouseEvent = { [weak connection] type, point in
            guard let token = connection?.sessionToken else { return }
            let event = MouseEvent(sessionToken: token, type: type, x: Double(point.x), y: Double(point.y))
            connection?.sendJSON(.mouseEvent, payload: event)
        }

        pipeline.gestureHandler.onScrollEvent = { [weak connection] deltaX, deltaY in
            guard let token = connection?.sessionToken else { return }
            let event = ScrollEvent(sessionToken: token, deltaX: Double(deltaX), deltaY: Double(deltaY))
            connection?.sendJSON(.scrollEvent, payload: event)
        }

        pipeline.gestureHandler.attach(to: view)
    }

    // MARK: - Keyboard

    private func sendKeyEvent(keyCode: UInt16, character: String) {
        guard let token = connection.sessionToken else { return }

        var modifiers = activeModifiers.rawValue
        if character.count == 1, let first = character.first, KeyCodeMap.requiresShift(first) {
            modifiers |= ModifierKeys.shift.rawValue
        }

        let downEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: true, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: downEvent)

        let upEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: false, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: upEvent)

        activeModifiers = ModifierKeys()
    }

    private func cleanup() {
        pipeline.reset()
        connection.onFrameReceived = nil
    }
}
