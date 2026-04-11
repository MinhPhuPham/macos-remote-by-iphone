import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// H.264 hardware decoder using VideoToolbox.
/// Receives SPS/PPS config and NAL units, outputs CVPixelBuffers.
final class VideoDecoder {

    /// Called with each decoded pixel buffer.
    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    // MARK: - Configuration

    /// Initialize the decoder with SPS and PPS parameter sets from the server.
    func configure(sps: Data, pps: Data) throws {
        // Tear down existing session.
        invalidate()

        // Build CMFormatDescription from SPS + PPS.
        let parameterSets: [Data] = [sps, pps]
        let parameterSetPointers = parameterSets.map { data -> UnsafePointer<UInt8> in
            data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        }
        let parameterSetSizes = parameterSets.map { $0.count }

        var formatDesc: CMFormatDescription?
        let status = parameterSetPointers.withUnsafeBufferPointer { pointers in
            parameterSetSizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers.baseAddress!,
                    parameterSetSizes: sizes.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )
            }
        }

        guard status == noErr, let desc = formatDesc else {
            throw DecoderError.formatCreationFailed(status)
        }

        self.formatDescription = desc
        try createSession(formatDescription: desc)
    }

    // MARK: - Decoding

    /// Decode a single H.264 NAL unit (as received in a VIDEO_FRAME message).
    func decode(nalData: Data, presentationTime: CMTime = CMTime(value: 0, timescale: 1)) {
        guard let session = session, let formatDesc = formatDescription else { return }

        // Wrap NAL data in a CMBlockBuffer.
        var blockBuffer: CMBlockBuffer?
        nalData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let _ = CMBlockBufferCreateWithMemoryBlock(
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
        }

        guard let buffer = blockBuffer else { return }

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

        guard sampleStatus == noErr, let sample = sampleBuffer else { return }

        // Decode.
        var flagsOut = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample,
                                          flags: [._EnableAsynchronousDecompression],
                                          infoFlagsOut: &flagsOut)
    }

    // MARK: - Lifecycle

    func invalidate() {
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    // MARK: - Internal

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

        // Set the output handler.
        VTDecompressionSessionSetOutputHandler(decompSession) { [weak self] status, _, imageBuffer, presentationTimeStamp, _ in
            guard status == noErr, let pixelBuffer = imageBuffer else { return }
            self?.onDecodedFrame?(pixelBuffer, presentationTimeStamp)
        }
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
