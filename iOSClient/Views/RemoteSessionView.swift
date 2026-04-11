import SwiftUI
import CoreMedia

// MARK: - Session Pipeline Coordinator

/// Owns the video pipeline and gesture handler as a single `ObservableObject`.
/// Using `@StateObject` ensures stable identity across SwiftUI view updates.
final class SessionPipeline: ObservableObject {

    let displayView = VideoDisplayUIView()
    let videoDecoder = VideoDecoder()
    let gestureHandler = GestureHandler()

    @Published private(set) var fps: Int = 0
    private var frameCount: Int = 0
    private var lastFPSUpdate = Date()

    func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            fps = frameCount
            frameCount = 0
            lastFPSUpdate = now
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
        .onDisappear { pipeline.reset(); connection.onFrameReceived = nil }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remote desktop session")
    }

    // MARK: - Subviews

    private var videoLayer: some View {
        VideoDisplayView(displayView: pipeline.displayView)
            .ignoresSafeArea()
            .onAppear { setupGestures() }
    }

    private var overlayControls: some View {
        VStack(spacing: 0) {
            if showStatusBar {
                ConnectionStatusBar(
                    fps: pipeline.fps,
                    isConnected: connection.state == .connected
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
        pipeline.videoDecoder.onDecodedFrame = { pixelBuffer, timestamp in
            if let sampleBuffer = CMSampleBuffer.create(from: pixelBuffer, presentationTime: timestamp) {
                DispatchQueue.main.async {
                    self.pipeline.displayView.enqueue(sampleBuffer)
                    self.pipeline.updateFPS()
                }
            }
        }

        connection.onFrameReceived = { frame in
            switch frame.type {
            case .videoConfig:
                handleVideoConfig(frame)
            case .videoFrame:
                pipeline.videoDecoder.decode(nalData: frame.payload)
            case .configUpdate:
                handleConfigUpdate(frame)
            default:
                break
            }
        }
    }

    private func handleVideoConfig(_ frame: ProtocolFrame) {
        let data = frame.payload
        guard data.count > 4 else { return }
        let spsLength = Int(data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard data.count >= 4 + spsLength else { return }

        let sps = data.subdata(in: 4..<(4 + spsLength))
        let pps = data.subdata(in: (4 + spsLength)..<data.count)

        try? pipeline.videoDecoder.configure(sps: sps, pps: pps)
    }

    private func handleConfigUpdate(_ frame: ProtocolFrame) {
        guard let config = try? MessageCodec.decodePayload(ConfigUpdate.self, from: frame) else { return }
        pipeline.gestureHandler.serverScreenWidth = CGFloat(config.screenWidth)
        pipeline.gestureHandler.serverScreenHeight = CGFloat(config.screenHeight)
    }

    // MARK: - Gestures

    private func setupGestures() {
        pipeline.gestureHandler.onMouseEvent = { type, point in
            guard let token = connection.sessionToken else { return }
            let event = MouseEvent(sessionToken: token, type: type, x: Double(point.x), y: Double(point.y))
            connection.sendJSON(.mouseEvent, payload: event)
        }

        pipeline.gestureHandler.onScrollEvent = { deltaX, deltaY in
            guard let token = connection.sessionToken else { return }
            let event = ScrollEvent(sessionToken: token, deltaX: Double(deltaX), deltaY: Double(deltaY))
            connection.sendJSON(.scrollEvent, payload: event)
        }

        pipeline.gestureHandler.attach(to: pipeline.displayView)
    }

    // MARK: - Keyboard

    private func sendKeyEvent(keyCode: UInt16, character: String) {
        guard let token = connection.sessionToken else { return }

        var modifiers = activeModifiers.rawValue
        if character.count == 1, KeyCodeMap.requiresShift(character.first!) {
            modifiers |= ModifierKeys.shift.rawValue
        }

        let downEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: true, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: downEvent)

        let upEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: false, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: upEvent)

        // Auto-deactivate modifiers after keypress (sticky behavior).
        activeModifiers = ModifierKeys()
    }
}
