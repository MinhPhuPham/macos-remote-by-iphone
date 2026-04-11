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

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func flush() {
        displayLayer.flush()
    }
}

/// SwiftUI wrapper for the video display layer.
/// Creates the UIView in `makeUIView` (proper UIViewRepresentable lifecycle).
struct VideoDisplayView: UIViewRepresentable {

    /// Reference to the pipeline's display view, set after creation.
    let onViewCreated: (VideoDisplayUIView) -> Void

    func makeUIView(context: Context) -> VideoDisplayUIView {
        let view = VideoDisplayUIView()
        onViewCreated(view)
        return view
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {}

    static func dismantleUIView(_ uiView: VideoDisplayUIView, coordinator: ()) {
        uiView.flush()
    }
}

/// Helper to create CMSampleBuffer from a CVPixelBuffer.
/// Caches the format description to avoid per-frame allocation.
final class SampleBufferFactory {

    private var cachedFormatDescription: CMVideoFormatDescription?
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    func create(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Rebuild format description only when dimensions change.
        if cachedFormatDescription == nil || width != cachedWidth || height != cachedHeight {
            var formatDesc: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: nil,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc
            )
            cachedFormatDescription = formatDesc
            cachedWidth = width
            cachedHeight = height
        }

        guard let formatDesc = cachedFormatDescription else { return nil }

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
