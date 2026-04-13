import AVFoundation
import CoreMedia
import SwiftUI

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
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        layer.addSublayer(displayLayer)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Disable implicit animations to prevent flicker during rotation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
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

    /// Returns the rect within bounds where video is actually displayed (aspect-fit).
    func videoRect(forScreenWidth screenW: CGFloat, screenHeight screenH: CGFloat) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, screenW > 0, screenH > 0 else {
            return bounds
        }
        let videoAspect = screenW / screenH
        let viewAspect = bounds.width / bounds.height

        if videoAspect > viewAspect {
            let height = bounds.width / videoAspect
            return CGRect(x: 0, y: (bounds.height - height) / 2,
                          width: bounds.width, height: height)
        } else {
            let width = bounds.height * videoAspect
            return CGRect(x: (bounds.width - width) / 2, y: 0,
                          width: width, height: bounds.height)
        }
    }
}

// MARK: - SwiftUI Wrapper

/// Wraps `VideoDisplayUIView` for SwiftUI. Uses a Coordinator to hold the reference
/// so we never mutate external state during `makeUIView` (avoids AttributeGraph cycles).
struct VideoDisplayView: UIViewRepresentable {

    /// Coordinator stores the view reference and wires callbacks AFTER creation.
    final class Coordinator {
        var displayView: VideoDisplayUIView?
        var onViewReady: ((VideoDisplayUIView) -> Void)?
    }

    /// Called once after the UIView is created and laid out.
    let onViewReady: (VideoDisplayUIView) -> Void

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onViewReady = onViewReady
        return c
    }

    func makeUIView(context: Context) -> VideoDisplayUIView {
        let view = VideoDisplayUIView()
        context.coordinator.displayView = view
        return view
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {
        // Fire onViewReady exactly once, after the view has a non-zero size.
        if let callback = context.coordinator.onViewReady, uiView.bounds.size != .zero {
            context.coordinator.onViewReady = nil
            callback(uiView)
        }
    }

    static func dismantleUIView(_ uiView: VideoDisplayUIView, coordinator: Coordinator) {
        uiView.flush()
        coordinator.displayView = nil
    }
}

// MARK: - Sample Buffer Factory

/// Creates CMSampleBuffer from CVPixelBuffer. Caches format description.
final class SampleBufferFactory {

    private var cachedFormatDescription: CMVideoFormatDescription?
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    func create(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

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
