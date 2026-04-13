import CoreMedia
import Foundation
import os
import VideoToolbox

/// H.264 hardware encoder using VideoToolbox.
/// Encodes CVPixelBuffer frames and outputs NAL units ready for network transmission.
final class VideoEncoder {

    var onEncodedFrame: ((Data, Bool) -> Void)?  // (data, isKeyframe)
    var onVideoConfig: ((Data, Data) -> Void)?   // (sps, pps)

    private var session: VTCompressionSession?
    private var hasEmittedConfig = false
    private var pendingForceKeyframe = false
    private var hasLoggedFirstEncode = false
    private var encodedFrameCount: Int = 0

    private let width: Int32
    private let height: Int32

    init(width: Int, height: Int) {
        self.width = Int32(width)
        self.height = Int32(height)
    }

    // MARK: - Setup

    func start(bitrate: Int = MyRemoteConstants.LAN.defaultBitrate,
               frameRate: Int = MyRemoteConstants.LAN.defaultFrameRate) throws {

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw EncoderError.sessionCreationFailed(status)
        }

        self.session = session

        // Real-time encoding with hardware acceleration.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        // High profile for better compression efficiency at the same bitrate.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)

        // Average bitrate — the encoder targets this over time.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)

        // Data rate limit: allow 2× burst over 1 second for sharp transitions
        // (e.g., opening a new window). Without burst headroom, quality drops
        // on sudden visual changes.
        let dataRateLimit = [Double(bitrate) * 2.0 / 8.0, 1.0] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: dataRateLimit)

        // Keyframe every 2 seconds (at 30fps = every 60 frames).
        // More frequent keyframes = faster recovery from corruption,
        // but slightly larger stream.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: (frameRate * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: 2.0 as CFNumber)

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: frameRate as CFNumber)

        // No B-frames — reduces latency (no frame reordering needed).
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        // Prioritize low latency over maximum compression.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowTemporalCompression,
                             value: kCFBooleanTrue)

        VTCompressionSessionPrepareToEncodeFrames(session)
        Log.encoder.info("Encoder started: \(self.width)x\(self.height) bitrate=\(bitrate) fps=\(frameRate)")
    }

    func stop() {
        Log.encoder.info("Encoder stopped")
        if let session = session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        hasEmittedConfig = false
        pendingForceKeyframe = false
        hasLoggedFirstEncode = false
        encodedFrameCount = 0
    }

    // MARK: - Encoding

    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session = session else { return }

        if !hasLoggedFirstEncode {
            Log.encoder.info("First frame encoding")
            hasLoggedFirstEncode = true
        }

        // Build frame properties — include force-keyframe if pending.
        var frameProperties: CFDictionary?
        if pendingForceKeyframe {
            let props: [CFString: Any] = [
                kVTEncodeFrameOptionKey_ForceKeyFrame: true
            ]
            frameProperties = props as CFDictionary
            pendingForceKeyframe = false
        }

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else { return }
            self?.processSampleBuffer(sampleBuffer)
        }

        if status != noErr {
            Log.encoder.warning("Encode error: \(status)")
        }
    }

    /// Force an IDR (keyframe) on the next encode call.
    func forceKeyframe() {
        Log.encoder.info("Keyframe forced")
        pendingForceKeyframe = true
    }

    // MARK: - Bitrate / Frame Rate Updates

    func setBitrate(_ bitrate: Int) {
        guard let session = session else { return }
        Log.encoder.info("Bitrate updated to \(bitrate)")
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
    }

    func setFrameRate(_ fps: Int) {
        guard let session = session else { return }
        Log.encoder.info("Frame rate updated to \(fps)")
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: fps as CFNumber)
    }

    // MARK: - Processing

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true

        if isKeyframe && !hasEmittedConfig {
            Log.encoder.info("Emitting video config (SPS/PPS)")
            extractVideoConfig(from: sampleBuffer)
            hasEmittedConfig = true
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                     totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer else { return }
        let data = Data(bytes: pointer, count: totalLength)

        encodedFrameCount += 1
        if encodedFrameCount % 30 == 0 {
            Log.encoder.debug("Encoded frame #\(self.encodedFrameCount): \(totalLength) bytes, keyframe=\(isKeyframe)")
        }

        onEncodedFrame?(data, isKeyframe)
    }

    private func extractVideoConfig(from sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        var spsSize = 0
        var spsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        var ppsSize = 0
        var ppsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        guard let sps = spsPointer, let pps = ppsPointer else { return }
        let spsData = Data(bytes: sps, count: spsSize)
        let ppsData = Data(bytes: pps, count: ppsSize)

        onVideoConfig?(spsData, ppsData)
    }
}

// MARK: - Errors

enum EncoderError: Error, LocalizedError {
    case sessionCreationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let status):
            return "Video encoder session creation failed: \(status)"
        }
    }
}
