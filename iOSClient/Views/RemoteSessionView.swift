import SwiftUI
import CoreMedia

/// Full-screen remote session view: video display + gesture input + toolbar.
struct RemoteSessionView: View {

    @ObservedObject var connection: ClientConnection

    @State private var activeModifiers = ModifierKeys()
    @State private var isKeyboardActive = false
    @State private var showStatusBar = true

    // Video pipeline.
    @State private var videoDisplayView = VideoDisplayUIView()
    @State private var videoDecoder = VideoDecoder()
    @State private var gestureHandler = GestureHandler()

    // Stats.
    @State private var fps: Int = 0
    @State private var frameCount: Int = 0
    @State private var lastFPSUpdate = Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video display with gestures.
            VideoDisplayView(displayView: videoDisplayView)
                .ignoresSafeArea()
                .onAppear { setupGestures() }

            // Overlays.
            VStack {
                if showStatusBar {
                    ConnectionStatusBar(
                        fps: fps,
                        isConnected: connection.state == .connected
                    )
                }

                Spacer()

                // Virtual keyboard (hidden input field).
                if isKeyboardActive {
                    VirtualKeyboardView(isActive: $isKeyboardActive) { char, keyCode, isSpecial in
                        sendKeyEvent(keyCode: keyCode, character: char)
                    }
                    .frame(height: 1) // Nearly invisible.
                }

                // Modifier keys + keyboard toggle.
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
        .onAppear { startVideoReceiver() }
        .onDisappear { cleanup() }
        .statusBarHidden()
    }

    // MARK: - Video Pipeline

    private func startVideoReceiver() {
        // Decode video frames from the connection.
        videoDecoder.onDecodedFrame = { [self] pixelBuffer, timestamp in
            if let sampleBuffer = CMSampleBuffer.create(from: pixelBuffer, presentationTime: timestamp) {
                DispatchQueue.main.async {
                    self.videoDisplayView.enqueue(sampleBuffer)
                    self.updateFPS()
                }
            }
        }

        connection.onFrameReceived = { [self] frame in
            switch frame.type {
            case .videoConfig:
                handleVideoConfig(frame)
            case .videoFrame:
                handleVideoFrame(frame)
            case .configUpdate:
                handleConfigUpdate(frame)
            default:
                break
            }
        }
    }

    private func handleVideoConfig(_ frame: ProtocolFrame) {
        // Payload: SPS length (4 bytes) + SPS data + PPS data.
        let data = frame.payload
        guard data.count > 4 else { return }
        let spsLength = Int(data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard data.count >= 4 + spsLength else { return }

        let sps = data.subdata(in: 4..<(4 + spsLength))
        let pps = data.subdata(in: (4 + spsLength)..<data.count)

        try? videoDecoder.configure(sps: sps, pps: pps)
    }

    private func handleVideoFrame(_ frame: ProtocolFrame) {
        videoDecoder.decode(nalData: frame.payload)
    }

    private func handleConfigUpdate(_ frame: ProtocolFrame) {
        guard let config = try? MessageCodec.decodePayload(ConfigUpdate.self, from: frame) else { return }
        gestureHandler.serverScreenWidth = CGFloat(config.screenWidth)
        gestureHandler.serverScreenHeight = CGFloat(config.screenHeight)
    }

    // MARK: - Gestures

    private func setupGestures() {
        gestureHandler.onMouseEvent = { [self] type, point in
            guard let token = connection.sessionToken else { return }
            let event = MouseEvent(sessionToken: token, type: type, x: Double(point.x), y: Double(point.y))
            connection.sendJSON(.mouseEvent, payload: event)
        }

        gestureHandler.onScrollEvent = { [self] deltaX, deltaY in
            guard let token = connection.sessionToken else { return }
            let event = ScrollEvent(sessionToken: token, deltaX: Double(deltaX), deltaY: Double(deltaY))
            connection.sendJSON(.scrollEvent, payload: event)
        }

        gestureHandler.attach(to: videoDisplayView)
    }

    // MARK: - Keyboard

    private func sendKeyEvent(keyCode: UInt16, character: String) {
        guard let token = connection.sessionToken else { return }

        var modifiers = activeModifiers.rawValue
        if KeyCodeMap.requiresShift(Character(character)) {
            modifiers |= ModifierKeys.shift.rawValue
        }

        // Key down.
        let downEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: true, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: downEvent)

        // Key up.
        let upEvent = KeyEvent(sessionToken: token, keyCode: keyCode, isDown: false, modifiers: modifiers)
        connection.sendJSON(.keyEvent, payload: upEvent)

        // Auto-deactivate modifiers after keypress (sticky behavior).
        activeModifiers = ModifierKeys()
    }

    // MARK: - FPS Counter

    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            fps = frameCount
            frameCount = 0
            lastFPSUpdate = now
        }
    }

    private func cleanup() {
        videoDecoder.invalidate()
        connection.onFrameReceived = nil
    }
}
