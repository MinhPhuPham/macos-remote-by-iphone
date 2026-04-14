import AppKit
import Combine
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

/// Manages screen capture via ScreenCaptureKit.
/// Supports multiple displays — call `listDisplays()` then `startCapture(displayIndex:)`.
final class ScreenCaptureManager: NSObject, ObservableObject {

    @Published private(set) var isCapturing = false
    @Published private(set) var captureError: String?

    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "\(AppConstants.queuePrefix).capture", qos: .userInteractive)

    private(set) var displayWidth: Int = 0
    private(set) var displayHeight: Int = 0
    /// Display origin in macOS global coordinate space (for multi-display mouse mapping).
    private(set) var displayOriginX: CGFloat = 0
    private(set) var displayOriginY: CGFloat = 0
    private var hasLoggedFirstPixelBuffer = false

    // MARK: - Permissions

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Display Discovery

    /// List all available displays.
    static func listDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.current
        return content.displays.enumerated().map { index, display in
            let isMain = (display.displayID == CGMainDisplayID())
            let name: String
            if isMain {
                name = "Main Display"
            } else {
                name = "Display \(index + 1)"
            }
            return DisplayInfo(
                id: index,
                name: name,
                width: display.width,
                height: display.height,
                isMain: isMain
            )
        }
    }

    // MARK: - Start / Stop

    func startCapture(
        displayIndex: Int = 0,
        scaleFactor: CGFloat = 0.5,
        frameRate: Int = MyRemoteConstants.LAN.defaultFrameRate
    ) async throws {
        guard Self.hasPermission() else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplayFound
        }

        let safeIndex = min(displayIndex, content.displays.count - 1)
        let display = content.displays[safeIndex]

        displayWidth = display.width
        displayHeight = display.height
        // Store global origin for multi-display coordinate mapping.
        let bounds = CGDisplayBounds(display.displayID)
        displayOriginX = bounds.origin.x
        displayOriginY = bounds.origin.y
        Log.capture.info("Capturing display \(safeIndex): \(display.width)x\(display.height) at origin (\(Int(bounds.origin.x)),\(Int(bounds.origin.y))) scale=\(scaleFactor)")

        let config = SCStreamConfiguration()
        // H.264 requires even dimensions.
        config.width = Int(CGFloat(display.width) * scaleFactor) & ~1
        config.height = Int(CGFloat(display.height) * scaleFactor) & ~1
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 2

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
        await MainActor.run { isCapturing = true }
    }

    func stopCapture() async {
        Log.capture.info("Screen capture stopped")
        try? await stream?.stopCapture()
        stream = nil
        hasLoggedFirstPixelBuffer = false
        await MainActor.run { isCapturing = false }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if !hasLoggedFirstPixelBuffer {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            Log.capture.info("First pixel buffer: \(w)x\(h)")
            hasLoggedFirstPixelBuffer = true
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onPixelBuffer?(pixelBuffer, timestamp)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("Capture stopped: \(error.localizedDescription)")
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
