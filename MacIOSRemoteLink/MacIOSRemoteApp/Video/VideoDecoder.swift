import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

/// H.264 hardware decoder using VideoToolbox.
/// Uses SYNCHRONOUS decode for natural backpressure — prevents memory exhaustion.
final class VideoDecoder {

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

        guard let session = session, let formatDesc = formatDescription else { return }

        decodeCount += 1
        let frameNum = decodeCount

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
            guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return }

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
            guard status == noErr, let sample = sampleBuffer else { return }

            var flagsOut = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sample,
                flags: [],
                infoFlagsOut: &flagsOut
            ) { [weak self] cbStatus, _, imageBuffer, pts, _ in
                guard cbStatus == noErr, let pixelBuffer = imageBuffer else { return }
                self?.onDecodedFrame?(pixelBuffer, pts)
            }

            if decodeStatus != noErr && frameNum <= 5 {
                Log.video.warning("DecodeFrame #\(frameNum) failed: \(decodeStatus)")
            }
        }
    }

    // MARK: - Lifecycle

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidateInternal()
    }

    private func invalidateInternal() {
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        decodeCount = 0
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
