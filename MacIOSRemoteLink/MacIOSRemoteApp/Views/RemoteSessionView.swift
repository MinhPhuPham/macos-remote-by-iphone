import Combine
import CoreMedia
import os
import SwiftUI

// MARK: - Session Pipeline

/// Owns video decode + display objects. Only `fps` is @Published to minimize SwiftUI diffs.
final class SessionPipeline: ObservableObject {

    var displayView: VideoDisplayUIView?
    let videoDecoder = VideoDecoder()
    let gestureHandler = GestureHandler()
    let sampleBufferFactory = SampleBufferFactory()

    @Published private(set) var fps: Int = 0
    private var frameCount: Int = 0
    private var lastFPSUpdate = Date()
    /// Monotonically increasing timestamp for AVSampleBufferDisplayLayer.
    var nextPTS: Int64 = 0

    func countFrame() {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastFPSUpdate) >= 1.0 {
            let newFPS = frameCount
            frameCount = 0
            lastFPSUpdate = now
            if newFPS != fps { fps = newFPS }
        }
    }

    func reset() {
        videoDecoder.invalidate()
        displayView?.flush()
        displayView = nil
        frameCount = 0
        fps = 0
    }
}

// MARK: - Remote Session View

struct RemoteSessionView: View {

    @ObservedObject var connection: ClientConnection
    @StateObject private var pipeline = SessionPipeline()

    @State private var activeModifiers = ModifierKeys()
    @State private var isKeyboardActive = false
    @State private var showControls = true
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Video layer — full screen, behind everything.
            Color.black.ignoresSafeArea()

            VideoDisplayView { view in
                pipeline.displayView = view
                pipeline.gestureHandler.attach(to: view)
                wireGestures()
                Log.session.info("Video display ready: \(Int(view.bounds.width))x\(Int(view.bounds.height))")
            }
            .ignoresSafeArea()

            // Controls overlay
            VStack(spacing: 0) {
                if showControls {
                    topBar
                }

                Spacer()

                if showControls {
                    bottomBar
                }
            }
            .padding(.bottom, keyboardHeight)
        }
        .ignoresSafeArea(.container)
        .onAppear { wireVideoPipeline() }
        .onDisappear { cleanup() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onReceive(keyboardPublisher) { height in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = height
            }
        }
    }

    // MARK: - Keyboard Publisher

    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> CGFloat in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }

        let willHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ -> CGFloat in 0 }

        return Publishers.Merge(willShow, willHide)
            .eraseToAnyPublisher()
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showControls = true
                }
            } label: {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
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
            // Hidden text field to capture keyboard input.
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

                Button { isKeyboardActive.toggle() } label: {
                    Image(systemName: isKeyboardActive ? "keyboard.fill" : "keyboard")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                Button { connection.disconnect() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
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

    // MARK: - Video Pipeline

    private func wireVideoPipeline() {
        pipeline.videoDecoder.onDecodedFrame = { [weak pipeline] pixelBuffer, timestamp in
            guard let pipeline = pipeline else { return }
            guard let sampleBuffer = pipeline.sampleBufferFactory.create(
                from: pixelBuffer, presentationTime: timestamp
            ) else { return }
            DispatchQueue.main.async { [weak pipeline] in
                pipeline?.displayView?.enqueue(sampleBuffer)
                pipeline?.countFrame()
            }
        }

        connection.onFrameReceived = { [weak pipeline] frame in
            guard let pipeline = pipeline else { return }
            switch frame.type {
            case .videoConfig:
                Self.handleVideoConfig(frame, pipeline: pipeline)
            case .videoFrame:
                // Each frame needs a unique increasing timestamp or
                // AVSampleBufferDisplayLayer silently drops them.
                pipeline.nextPTS += 1
                let pts = CMTime(value: pipeline.nextPTS, timescale: 30)
                pipeline.videoDecoder.decode(nalData: frame.payload, presentationTime: pts)
            case .configUpdate:
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
        }
    }

    // MARK: - Gestures

    private func wireGestures() {
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
        pipeline.reset()
        connection.onFrameReceived = nil
    }
}
