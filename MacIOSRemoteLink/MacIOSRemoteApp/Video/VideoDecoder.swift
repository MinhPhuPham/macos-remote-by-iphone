import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

/// H.264 hardware decoder using VideoToolbox.
/// Receives SPS/PPS config and NAL units, outputs CVPixelBuffers.
///
/// Uses SYNCHRONOUS decode to provide natural backpressure:
/// - The network thread blocks until decode completes (~1-2ms on hardware)
/// - This prevents frame accumulation that causes memory exhaustion
/// - Hardware H.264 decode is fast enough for 30fps real-time
final class VideoDecoder {

    /// Called with each decoded pixel buffer.
    /// With synchronous decode, this fires on the caller's thread inside `decode()`.
    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let lock = NSLock()

    // MARK: - Configuration

    func configure(sps: Data, pps: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        invalidateInternal()

        Log.video.info("Configuring decoder: SPS=\(sps.count)B PPS=\(pps.count)B")

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
        Log.video.info("Decoder session created")
    }

    // MARK: - Decoding

    private var decodeCount: Int = 0

    func decode(nalData: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard let session = session, let formatDesc = formatDescription else {
            Log.video.debug("Decode skipped — no session configured")
            return
        }

        decodeCount += 1
        let frameNum = decodeCount

        // Use the NAL data directly — synchronous decode completes before
        // withUnsafeBytes exits, so the pointer stays valid.
        nalData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var blockBuffer: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: UnsafeMutableRawPointer(mutating: baseAddress),
                blockLength: nalData.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: nalData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else {
                Log.video.warning("BlockBuffer failed: \(status)")
                return
            }

            var sampleBuffer: CMSampleBuffer?
            var timingInfo = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .zero,
                decodeTimeStamp: .invalid
            )

            status = CMSampleBufferCreateReady(
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
            guard status == noErr, let sample = sampleBuffer else {
                Log.video.warning("SampleBuffer failed: \(status)")
                return
            }

            // Truly synchronous decode — empty flags [].
            // Output handler fires BEFORE DecodeFrame returns.
            var flagsOut = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sample,
                flags: [],
                infoFlagsOut: &flagsOut
            ) { [weak self] cbStatus, _, imageBuffer, pts, _ in
                if cbStatus != noErr {
                    Log.video.warning("Decode callback error: \(cbStatus)")
                    return
                }
                guard let pixelBuffer = imageBuffer else {
                    Log.video.warning("Decode callback: no pixel buffer")
                    return
                }
                self?.onDecodedFrame?(pixelBuffer, pts)
            }

            if decodeStatus != noErr {
                Log.video.warning("DecodeFrame #\(frameNum) failed: \(decodeStatus)")
            } else if frameNum <= 3 || frameNum % 300 == 0 {
                Log.video.debug("Decoded frame #\(frameNum) (\(nalData.count)B)")
            }
        }
    }

    // MARK: - Lifecycle

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidateInternal()
        Log.video.info("Decoder invalidated")
    }

    private func invalidateInternal() {
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

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
