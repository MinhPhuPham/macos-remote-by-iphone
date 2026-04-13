import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

/// H.264 hardware decoder using VideoToolbox.
/// Receives SPS/PPS config and NAL units, outputs CVPixelBuffers.
/// Thread-safe: all access to session/formatDescription is serialized.
final class VideoDecoder {

    /// Called with each decoded pixel buffer (fires on VideoToolbox's internal thread).
    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let queue = DispatchQueue(label: "\(AppConstants.queuePrefix).videodecoder")

    // MARK: - Configuration

    /// Initialize the decoder with SPS and PPS parameter sets from the server.
    func configure(sps: Data, pps: Data) throws {
        try queue.sync {
            // Tear down existing session.
            invalidateInternal()

            // Build CMFormatDescription from SPS + PPS.
            // SAFETY: All pointer usage is nested inside withUnsafeBytes scopes
            // to prevent dangling pointer access.
            var formatDesc: CMFormatDescription?
            let status: OSStatus = sps.withUnsafeBytes { spsRaw in
                pps.withUnsafeBytes { ppsRaw in
                    guard let spsBase = spsRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let ppsBase = ppsRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return errSecParam
                    }
                    var pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                    var sizes: [Int] = [sps.count, pps.count]
                    return pointers.withUnsafeMutableBufferPointer { pointersPtr in
                        sizes.withUnsafeMutableBufferPointer { sizesPtr in
                            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: nil,
                                parameterSetCount: 2,
                                parameterSetPointers: pointersPtr.baseAddress!,
                                parameterSetSizes: sizesPtr.baseAddress!,
                                nalUnitHeaderLength: 4,
                                formatDescriptionOut: &formatDesc
                            )
                        }
                    }
                }
            }

            guard status == noErr, let desc = formatDesc else {
                throw DecoderError.formatCreationFailed(status)
            }

            self.formatDescription = desc
            try createSession(formatDescription: desc)
        }
    }

    // MARK: - Decoding

    /// Decode a single H.264 NAL unit (as received in a VIDEO_FRAME message).
    func decode(nalData: Data, presentationTime: CMTime = CMTime(value: 0, timescale: 1)) {
        queue.sync {
            guard let session = session, let formatDesc = formatDescription else { return }

            let nalLength = nalData.count

            // Create CMBlockBuffer with its own memory (safe for async decode).
            var blockBuffer: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: nil,
                blockLength: nalLength,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: nalLength,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else {
                Log.video.warning("Failed to create block buffer: \(status)")
                return
            }

            // Copy NAL data into the block buffer's owned memory.
            nalData.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                status = CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: buffer,
                    offsetIntoDestination: 0,
                    dataLength: nalLength
                )
            }
            guard status == kCMBlockBufferNoErr else {
                Log.video.warning("Failed to copy NAL data: \(status)")
                return
            }

            // Create CMSampleBuffer.
            var sampleBuffer: CMSampleBuffer?
            var timingInfo = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: .invalid
            )

            let sampleStatus = CMSampleBufferCreateReady(
                allocator: nil,
                dataBuffer: buffer,
                formatDescription: formatDesc,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            guard sampleStatus == noErr, let sample = sampleBuffer else {
                Log.video.warning("Failed to create sample buffer: \(sampleStatus)")
                return
            }

            // Decode with inline output handler (VTDecompressionSessionSetOutputHandler
            // is not available on iOS).
            var flagsOut = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sample,
                flags: [._EnableAsynchronousDecompression],
                infoFlagsOut: &flagsOut
            ) { [weak self] status, _, imageBuffer, presentationTimeStamp, _ in
                guard status == noErr, let pixelBuffer = imageBuffer else { return }
                self?.onDecodedFrame?(pixelBuffer, presentationTimeStamp)
            }

            if decodeStatus != noErr {
                Log.video.warning("Decode frame failed: \(decodeStatus)")
            }
        }
    }

    // MARK: - Lifecycle

    func invalidate() {
        queue.sync { invalidateInternal() }
    }

    private func invalidateInternal() {
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    // MARK: - Internal

    /// Must be called on `queue`.
    private func createSession(formatDescription: CMVideoFormatDescription) throws {
        let outputAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: outputAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard status == noErr, let decompSession = session else {
            throw DecoderError.sessionCreationFailed(status)
        }

        self.session = decompSession
    }
}

// MARK: - Errors

enum DecoderError: Error, LocalizedError {
    case formatCreationFailed(OSStatus)
    case sessionCreationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed(let s):
            return "Failed to create video format description: \(s)"
        case .sessionCreationFailed(let s):
            return "Failed to create decompression session: \(s)"
        }
    }
}
