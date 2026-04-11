import SwiftUI
import AVFoundation
import CoreMedia

/// UIKit view that hosts an AVSampleBufferDisplayLayer for rendering decoded H.264 frames.
final class VideoDisplayUIView: UIView {

    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        layer.addSublayer(displayLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }

    /// Enqueue a decoded sample buffer for display.
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    /// Flush the display layer (e.g., on keyframe request or reconnect).
    func flush() {
        displayLayer.flush()
    }
}

/// SwiftUI wrapper for the video display layer.
struct VideoDisplayView: UIViewRepresentable {

    let displayView: VideoDisplayUIView

    func makeUIView(context: Context) -> VideoDisplayUIView {
        displayView
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {}
}

/// Helper to create CMSampleBuffer from a CVPixelBuffer (for enqueuing into display layer).
extension CMSampleBuffer {

    static func create(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let formatDesc = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
