import AVFoundation
import CoreMedia
import os
import SwiftUI

/// UIKit view that hosts an AVSampleBufferDisplayLayer for real-time H.264 rendering.
///
/// No `controlTimebase` is set — Apple docs: "If you don't set this property,
/// the layer renders all enqueued sample buffers immediately."
/// This is exactly what we need for real-time streaming.
final class VideoDisplayUIView: UIView {

    let displayLayer = AVSampleBufferDisplayLayer()

    var onReady: ((VideoDisplayUIView) -> Void)?
    private var didFireReady = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        layer.addSublayer(displayLayer)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        // No controlTimebase → layer displays frames immediately when enqueued.
        Log.video.debug("Display layer created (immediate mode, no timebase)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Use bounds + position (not frame) so CATransform3D for zoom is preserved.
        // Setting frame when transform != identity has undefined behavior.
        displayLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        if !didFireReady && bounds.width > 0 && bounds.height > 0 {
            didFireReady = true
            Log.video.info("View ready: \(Int(self.bounds.width))x\(Int(self.bounds.height))")
            onReady?(self)
            onReady = nil
        }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            Log.video.warning("Display layer failed — flushing and retrying")
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func flush() {
        Log.video.debug("Display layer flushed")
        displayLayer.flush()
    }

    /// The rect where video actually displays (aspect-fit letterboxing).
    func videoRect(forScreenWidth screenW: CGFloat, screenHeight screenH: CGFloat) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, screenW > 0, screenH > 0 else {
            return bounds
        }
        let videoAspect = screenW / screenH
        let viewAspect = bounds.width / bounds.height

        if videoAspect > viewAspect {
            let h = bounds.width / videoAspect
            return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        } else {
            let w = bounds.height * videoAspect
            return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
        }
    }
}

// MARK: - SwiftUI Wrapper

struct VideoDisplayView: UIViewRepresentable {

    let onViewReady: (VideoDisplayUIView) -> Void

    func makeUIView(context: Context) -> VideoDisplayUIView {
        let view = VideoDisplayUIView()
        view.onReady = onViewReady
        return view
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {}

    static func dismantleUIView(_ uiView: VideoDisplayUIView, coordinator: ()) {
        uiView.flush()
    }
}

// MARK: - Sample Buffer Factory

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
                allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc
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
            allocator: nil, imageBuffer: pixelBuffer,
            formatDescription: formatDesc, sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
