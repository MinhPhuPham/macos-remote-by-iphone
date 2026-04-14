import Combine
import CoreMedia
import os
import SwiftUI

// MARK: - Session Pipeline

final class SessionPipeline: ObservableObject {

    var displayView: VideoDisplayUIView?
    let videoDecoder = VideoDecoder()
    let gestureHandler = GestureHandler()
    let sampleBufferFactory = SampleBufferFactory()

    @Published private(set) var fps: Int = 0
    private let _frameCount = OSAllocatedUnfairLock(initialState: 0)
    private var fpsTimer: Timer?
    var nextPTS: Int64 = 0

    func startFPSCounter() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let count = self._frameCount.withLock { val -> Int in
                let c = val; val = 0; return c
            }
            if count != self.fps { self.fps = count }
        }
    }

    func incrementFrameCount() {
        _frameCount.withLock { $0 += 1 }
    }

    func reset() {
        fpsTimer?.invalidate()
        fpsTimer = nil
        videoDecoder.invalidate()
        displayView?.flush()
        displayView = nil
        _frameCount.withLock { $0 = 0 }
        fps = 0
        nextPTS = 0
    }
}

// MARK: - Remote Session View

struct RemoteSessionView: View {

    @ObservedObject var connection: ClientConnection
    @StateObject private var pipeline = SessionPipeline()
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeModifiers = ModifierKeys()
    @State private var isKeyboardActive = false
    @State private var showControls = true
    @State private var isPipelineWired = false

    var body: some View {
        ZStack {
            // Video fills entire screen.
            Color.black.ignoresSafeArea()

            VideoDisplayView { view in
                Log.session.info("onViewReady — \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                pipeline.displayView = view
                pipeline.gestureHandler.attach(to: view)
                wireGestures()
                wireVideoPipeline()
                pipeline.startFPSCounter()
                connection.requestKeyframe()
                isPipelineWired = true
            }
            .ignoresSafeArea()

            // Toolbar overlay — positioned at top and bottom.
            // Does NOT ignore keyboard safe area → SwiftUI pushes it above keyboard.
            VStack(spacing: 0) {
                if showControls { topBar }
                Spacer()
                if showControls { bottomBar }
            }
        }
        .ignoresSafeArea(.container)  // Ignore container edges but NOT keyboard.
        .onDisappear { cleanup() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isPipelineWired {
                Log.session.info("Foregrounded — requesting keyframe")
                connection.requestKeyframe()
                pipeline.displayView?.flush()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connection.state == .connected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text("\(pipeline.fps) FPS")
                .font(.caption2.monospacedDigit())
            Spacer()
            Button {
                showControls = false
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showControls = true
                }
            } label: {
                Image(systemName: "eye.slash")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Hidden text field that captures keyboard input.
            if isKeyboardActive {
                VirtualKeyboardView(isActive: $isKeyboardActive) { char, keyCode, _ in
                    sendKeyEvent(keyCode: keyCode, character: char)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }

            HStack(spacing: 12) {
                modifierButton("\u{2318}", modifier: .command)
                modifierButton("\u{2325}", modifier: .option)
                modifierButton("\u{2303}", modifier: .control)
                modifierButton("\u{21E7}", modifier: .shift)

                Divider().frame(height: 20)

                // Keyboard toggle
                Button { isKeyboardActive.toggle() } label: {
                    Image(systemName: isKeyboardActive ? "keyboard.fill" : "keyboard")
                        .font(.title3).foregroundStyle(.white)
                }

                // Display picker (only if multiple displays)
                if connection.availableDisplays.count > 1 {
                    Menu {
                        ForEach(connection.availableDisplays) { display in
                            Button {
                                switchDisplay(to: display.id)
                            } label: {
                                Label(
                                    "\(display.name) (\(display.width)×\(display.height))",
                                    systemImage: display.id == connection.currentDisplayIndex
                                        ? "checkmark.circle.fill" : "display"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.title3).foregroundStyle(.white)
                    }
                }

                Spacer()

                // Disconnect
                Button { connection.disconnect() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5))
        }
    }

    private func modifierButton(_ label: String, modifier: ModifierKeys) -> some View {
        let isActive = activeModifiers.contains(modifier)
        return Button {
            if isActive { activeModifiers.remove(modifier) }
            else { activeModifiers.insert(modifier) }
        } label: {
            Text(label)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(isActive ? Color.accentColor : Color.white.opacity(0.15),
                             in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display Switch

    private func switchDisplay(to index: Int) {
        guard index != connection.currentDisplayIndex else { return }
        Log.session.info("Switching to display \(index)")
        pipeline.displayView?.flush()
        pipeline.videoDecoder.invalidate()
        pipeline.gestureHandler.resetZoom()
        pipeline.nextPTS = 0
        connection.selectDisplay(index: index)
    }

    // MARK: - Video Pipeline

    private func wireVideoPipeline() {
        Log.session.info("Video pipeline wired")

        pipeline.videoDecoder.onDecodedFrame = { [weak pipeline] pixelBuffer, _ in
            guard let pipeline = pipeline else { return }
            pipeline.nextPTS += 1
            let pts = CMTime(value: pipeline.nextPTS, timescale: 30)
            guard let sampleBuffer = pipeline.sampleBufferFactory.create(
                from: pixelBuffer, presentationTime: pts
            ) else { return }
            guard let displayView = pipeline.displayView else { return }
            displayView.enqueue(sampleBuffer)
            pipeline.incrementFrameCount()
        }

        connection.onFrameReceived = { [weak pipeline] frame in
            guard let pipeline = pipeline else { return }
            switch frame.type {
            case .videoConfig:
                Log.session.info("videoConfig received (\(frame.payload.count)B)")
                Self.handleVideoConfig(frame, pipeline: pipeline)
            case .videoFrame:
                pipeline.videoDecoder.decode(nalData: frame.payload)
            case .configUpdate:
                Log.session.info("configUpdate received")
                Self.handleConfigUpdate(frame, pipeline: pipeline)
            default:
                break
            }
        }
    }

    private static func handleVideoConfig(_ frame: ProtocolFrame, pipeline: SessionPipeline) {
        let data = frame.payload
        guard data.count > 4 else { return }
        let spsLength = Int(data[0..<4].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        })
        guard data.count >= 4 + spsLength else { return }
        let sps = data.subdata(in: 4..<(4 + spsLength))
        let pps = data.subdata(in: (4 + spsLength)..<data.count)
        do {
            try pipeline.videoDecoder.configure(sps: sps, pps: pps)
            Log.session.info("Decoder configured: SPS=\(sps.count)B PPS=\(pps.count)B")
        } catch {
            Log.session.error("Decoder config failed: \(error.localizedDescription)")
        }
    }

    private static func handleConfigUpdate(_ frame: ProtocolFrame, pipeline: SessionPipeline) {
        guard let config = try? MessageCodec.decodePayload(ConfigUpdate.self, from: frame) else { return }
        Log.session.info("Screen: \(config.screenWidth)x\(config.screenHeight) @\(config.fps)fps")
        DispatchQueue.main.async { [weak pipeline] in
            pipeline?.gestureHandler.serverScreenWidth = CGFloat(config.screenWidth)
            pipeline?.gestureHandler.serverScreenHeight = CGFloat(config.screenHeight)
            pipeline?.gestureHandler.resetZoom()
        }
    }

    // MARK: - Gestures

    private func wireGestures() {
        Log.session.info("Gesture callbacks wired")
        pipeline.gestureHandler.onMouseEvent = { [weak connection] type, point in
            guard let token = connection?.sessionToken else { return }
            connection?.sendJSON(.mouseEvent,
                                 payload: MouseEvent(sessionToken: token, type: type,
                                                     x: Double(point.x), y: Double(point.y)))
        }
        pipeline.gestureHandler.onScrollEvent = { [weak connection] deltaX, deltaY in
            guard let token = connection?.sessionToken else { return }
            connection?.sendJSON(.scrollEvent,
                                 payload: ScrollEvent(sessionToken: token,
                                                      deltaX: Double(deltaX), deltaY: Double(deltaY)))
        }
    }

    // MARK: - Keyboard

    private func sendKeyEvent(keyCode: UInt16, character: String) {
        guard let token = connection.sessionToken else { return }
        var modifiers = activeModifiers.rawValue
        if character.count == 1, let first = character.first, KeyCodeMap.requiresShift(first) {
            modifiers |= ModifierKeys.shift.rawValue
        }
        connection.sendJSON(.keyEvent,
                            payload: KeyEvent(sessionToken: token, keyCode: keyCode,
                                              isDown: true, modifiers: modifiers))
        connection.sendJSON(.keyEvent,
                            payload: KeyEvent(sessionToken: token, keyCode: keyCode,
                                              isDown: false, modifiers: modifiers))
        activeModifiers = ModifierKeys()
    }

    private func cleanup() {
        Log.session.info("Session cleanup")
        isPipelineWired = false
        pipeline.reset()
        connection.onFrameReceived = nil
    }
}
