import Foundation

/// Encodes and decodes `ProtocolFrame` messages over a byte stream.
/// Thread-safe accumulation buffer for partial TCP reads.
public final class MessageCodec: @unchecked Sendable {

    private var buffer = Data()
    private let lock = NSLock()

    public init() {}

    // MARK: - Encoding

    /// Encode a `Codable` payload into a `ProtocolFrame`.
    public static func encode<T: Encodable>(_ type: MessageType, payload: T) throws -> Data {
        let json = try JSONEncoder().encode(payload)
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
    public func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
    }

    /// Try to extract all complete frames from the buffer.
    /// Returns decoded frames; partial data remains in the buffer.
    public func decodeAvailableFrames() -> [ProtocolFrame] {
        lock.lock()
        defer { lock.unlock() }

        var frames: [ProtocolFrame] = []
        while let (frame, consumed) = ProtocolFrame.decode(from: buffer) {
            frames.append(frame)
            buffer.removeFirst(consumed)
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
        return try JSONDecoder().decode(type, from: frame.payload)
    }
}
