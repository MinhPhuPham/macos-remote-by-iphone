import AppKit
import Combine
import CoreMedia
import Foundation
import JPMacIPRemoteShared
import ScreenCaptureKit

/// Manages screen capture via ScreenCaptureKit.
final class ScreenCaptureManager: NSObject, ObservableObject {

    @Published private(set) var isCapturing = false
    @Published private(set) var captureError: String?

    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "\(AppConstants.queuePrefix).capture", qos: .userInteractive)

    private(set) var displayWidth: Int = 0
    private(set) var displayHeight: Int = 0

    // MARK: - Permissions

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Start / Stop

    func startCapture(scaleFactor: CGFloat = 0.5, frameRate: Int = MyRemoteConstants.LAN.defaultFrameRate) async throws {
        guard Self.hasPermission() else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        displayWidth = display.width
        displayHeight = display.height

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
        await MainActor.run { isCapturing = true }
    }

    func stopCapture() async {
        try? await stream?.stopCapture()
        stream = nil
        await MainActor.run { isCapturing = false }
    }

    func updateConfiguration(scaleFactor: CGFloat, frameRate: Int) async throws {
        guard let stream = stream else { return }
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { return }

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        try await stream.updateConfiguration(config)
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onPixelBuffer?(pixelBuffer, timestamp)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            self?.captureError = "Capture stopped: \(error.localizedDescription)"
        }
    }
}

// MARK: - Errors

enum CaptureError: Error, LocalizedError {
    case noDisplayFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display found for capture."
        case .permissionDenied: return "Screen recording permission not granted."
        }
    }
}
