import Foundation

/// Encodes and decodes `ProtocolFrame` messages over a byte stream.
/// Thread-safe accumulation buffer for partial TCP reads.
public final class MessageCodec: @unchecked Sendable {

    private var buffer = Data()
    private let lock = NSLock()

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public init() {}

    // MARK: - Encoding

    /// Encode a `Codable` payload into a wire-format frame.
    public static func encode<T: Encodable>(_ type: MessageType, payload: T) throws -> Data {
        let json = try encoder.encode(payload)
        let frame = ProtocolFrame(type: type, payload: json)
        return frame.encode()
    }

    /// Encode a frame with no payload (heartbeat, disconnect, keyframe request).
    public static func encode(_ type: MessageType) -> Data {
        let frame = ProtocolFrame(type: type)
        return frame.encode()
    }

    /// Encode raw data payload (video frames, video config).
    public static func encodeRaw(_ type: MessageType, payload: Data) -> Data {
        let frame = ProtocolFrame(type: type, payload: payload)
        return frame.encode()
    }

    // MARK: - Decoding (streaming)

    /// Append incoming bytes to the internal buffer.
    /// Returns false if the buffer exceeds the max size (connection should be dropped).
    @discardableResult
    public func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        if buffer.count > MyRemoteConstants.maxBufferSize {
            buffer.removeAll()
            return false
        }
        return true
    }

    /// Try to extract all complete frames from the buffer.
    /// Returns decoded frames; partial data remains in the buffer.
    /// Unknown message types are silently skipped (bytes consumed but no frame emitted).
    public func decodeAvailableFrames() -> [ProtocolFrame] {
        lock.lock()
        defer { lock.unlock() }

        var frames: [ProtocolFrame] = []
        var offset = 0
        let bufferSlice = buffer

        while offset < bufferSlice.count {
            let startIdx = bufferSlice.startIndex + offset
            let remaining = bufferSlice[startIdx..<bufferSlice.endIndex]
            guard let (frame, consumed) = ProtocolFrame.decode(from: remaining) else {
                break // Not enough data for a complete frame.
            }
            if let frame = frame {
                frames.append(frame)
            }
            // Always advance — even for unknown types — to prevent infinite loops.
            offset += consumed
        }

        // Compact the buffer once after processing all frames (O(n) once, not per frame).
        if offset > 0 {
            buffer.removeFirst(offset)
        }

        return frames
    }

    /// Reset the internal buffer (e.g., on disconnect).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    // MARK: - Payload Decoding Helpers

    /// Decode a JSON payload from a frame.
    public static func decodePayload<T: Decodable>(_ type: T.Type, from frame: ProtocolFrame) throws -> T {
        return try decoder.decode(type, from: frame.payload)
    }
}
