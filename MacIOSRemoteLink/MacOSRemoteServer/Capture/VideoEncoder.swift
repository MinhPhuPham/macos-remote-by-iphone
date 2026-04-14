import CoreMedia
import Foundation
import os
import VideoToolbox

/// H.264 hardware encoder with low-latency rate control.
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

        // Try low-latency rate control first, fall back to standard if unavailable.
        let lowLatencySpec: CFDictionary = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ] as CFDictionary

        var session: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: nil, width: width, height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: lowLatencySpec,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &session
        )

        if status != noErr {
            Log.encoder.info("Low-latency rate control unavailable, using standard encoder")
            status = VTCompressionSessionCreate(
                allocator: nil, width: width, height: height,
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil,
                compressionSessionOut: &session
            )
        }

        guard status == noErr, let session = session else {
            throw EncoderError.sessionCreationFailed(status)
        }

        self.session = session

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)

        let dataRateLimit = [Double(bitrate) * 2.0 / 8.0, 1.0] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: dataRateLimit)

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: (frameRate * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: 2.0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        Log.encoder.info("Encoder started: \(self.width)x\(self.height) bitrate=\(bitrate) fps=\(frameRate)")
    }

    func stop() {
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

    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session = session else { return }

        if !hasLoggedFirstEncode {
            Log.encoder.info("First frame encoding")
            hasLoggedFirstEncode = true
        }

        var frameProperties: CFDictionary?
        if pendingForceKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            pendingForceKeyframe = false
        }

        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime, duration: .invalid,
            frameProperties: frameProperties, infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else { return }
            self?.processSampleBuffer(sampleBuffer)
        }

        if status != noErr {
            Log.encoder.warning("Encode error: \(status)")
        }
    }

    func forceKeyframe() { pendingForceKeyframe = true }

    func setBitrate(_ bitrate: Int) {
        guard let session = session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
    }

    func setFrameRate(_ fps: Int) {
        guard let session = session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: fps as CFNumber)
    }

    // MARK: - Processing

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true

        if isKeyframe && !hasEmittedConfig {
            extractVideoConfig(from: sampleBuffer)
            hasEmittedConfig = true
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                     totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard let pointer = dataPointer else { return }

        encodedFrameCount += 1
        if encodedFrameCount % 30 == 0 {
            Log.encoder.debug("Frame #\(self.encodedFrameCount): \(totalLength)B keyframe=\(isKeyframe)")
        }

        onEncodedFrame?(Data(bytes: pointer, count: totalLength), isKeyframe)
    }

    private func extractVideoConfig(from sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        var spsSize = 0, spsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)

        var ppsSize = 0, ppsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)

        guard let sps = spsPointer, let pps = ppsPointer else { return }
        Log.encoder.info("Config: SPS=\(spsSize)B PPS=\(ppsSize)B")
        onVideoConfig?(Data(bytes: sps, count: spsSize), Data(bytes: pps, count: ppsSize))
    }
}

enum EncoderError: Error, LocalizedError {
    case sessionCreationFailed(OSStatus)
    var errorDescription: String? {
        "Video encoder session creation failed: \(status)"
    }
    private var status: OSStatus {
        switch self { case .sessionCreationFailed(let s): return s }
    }
}
