import Foundation

// MARK: - Message Types

/// All message types in the MyRemote binary protocol.
public enum MessageType: UInt8, Sendable {
    case authRequest     = 0x01
    case authResult      = 0x02
    case videoConfig     = 0x03
    case videoFrame      = 0x04
    case mouseEvent      = 0x05
    case keyEvent        = 0x06
    case scrollEvent     = 0x07
    case heartbeat       = 0x08
    case disconnect      = 0x09
    case keyframeRequest = 0x0A
    case configUpdate    = 0x0B
    case ping            = 0x0C  // RTT measurement: client → server
    case pong            = 0x0D  // RTT measurement: server → client
    case qualityUpdate   = 0x0E  // Client → Server: request bitrate/fps change
}

// MARK: - Protocol Frame

/// A single protocol frame: 1-byte type + 4-byte length + variable payload.
public struct ProtocolFrame: Sendable {
    public let type: MessageType
    public let payload: Data

    public init(type: MessageType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    /// Encode into wire format.
    public func encode() -> Data {
        var data = Data(capacity: 5 + payload.count)
        data.append(type.rawValue)
        var length = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(payload)
        return data
    }

    /// Attempt to decode one frame from the front of `data`.
    /// Returns the frame and total bytes consumed, or nil if not enough data.
    /// If the message type is unknown, returns nil for the frame but still
    /// reports the consumed byte count to prevent infinite loops.
    public static func decode(from data: Data) -> (frame: ProtocolFrame?, consumed: Int)? {
        guard data.count >= 5 else { return nil }
        let typeByte = data[data.startIndex]
        let lengthSlice = data[(data.startIndex + 1)..<(data.startIndex + 5)]
        let length = lengthSlice.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let payloadLength = Int(length)
        let totalLength = 5 + payloadLength

        // Reject oversized frames to prevent memory exhaustion (DoS protection).
        guard payloadLength <= MyRemoteConstants.maxFramePayloadSize else {
            return (frame: nil, consumed: totalLength)
        }

        guard data.count >= totalLength else { return nil }

        // Unknown type: skip the frame but still consume the bytes.
        guard let type = MessageType(rawValue: typeByte) else {
            return (frame: nil, consumed: totalLength)
        }

        let payload = data[(data.startIndex + 5)..<(data.startIndex + totalLength)]
        return (frame: ProtocolFrame(type: type, payload: Data(payload)), consumed: totalLength)
    }
}

// MARK: - Auth Payloads

/// Client → Server: authentication request.
public struct AuthRequest: Codable, Sendable {
    public let password: String
    public let deviceUUID: String
    public let deviceName: String

    public init(password: String, deviceUUID: String, deviceName: String) {
        self.password = password
        self.deviceUUID = deviceUUID
        self.deviceName = deviceName
    }
}

/// Server → Client: authentication result.
public struct AuthResult: Codable, Sendable {
    public let success: Bool
    public let sessionToken: String?
    public let reason: String?

    public init(success: Bool, sessionToken: String? = nil, reason: String? = nil) {
        self.success = success
        self.sessionToken = sessionToken
        self.reason = reason
    }
}

// MARK: - Input Event Payloads

/// Mouse event types.
public enum MouseEventType: String, Codable, Sendable {
    case move
    case leftDown
    case leftUp
    case rightDown
    case rightUp
}

/// Client → Server: mouse event.
public struct MouseEvent: Codable, Sendable {
    public let sessionToken: String
    public let type: MouseEventType
    public let x: Double
    public let y: Double

    public init(sessionToken: String, type: MouseEventType, x: Double, y: Double) {
        self.sessionToken = sessionToken
        self.type = type
        self.x = x
        self.y = y
    }
}

/// Client → Server: key event.
public struct KeyEvent: Codable, Sendable {
    public let sessionToken: String
    public let keyCode: UInt16
    public let isDown: Bool
    public let modifiers: UInt64

    public init(sessionToken: String, keyCode: UInt16, isDown: Bool, modifiers: UInt64) {
        self.sessionToken = sessionToken
        self.keyCode = keyCode
        self.isDown = isDown
        self.modifiers = modifiers
    }
}

/// Client → Server: scroll event.
public struct ScrollEvent: Codable, Sendable {
    public let sessionToken: String
    public let deltaX: Double
    public let deltaY: Double

    public init(sessionToken: String, deltaX: Double, deltaY: Double) {
        self.sessionToken = sessionToken
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

/// Server → Client: configuration update.
public struct ConfigUpdate: Codable, Sendable {
    public let screenWidth: Int
    public let screenHeight: Int
    public let fps: Int

    public init(screenWidth: Int, screenHeight: Int, fps: Int) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.fps = fps
    }
}

// MARK: - RTT & Adaptive Quality Payloads

/// Ping payload for RTT measurement.
public struct PingPayload: Codable, Sendable {
    public let timestamp: UInt64  // milliseconds since epoch

    public init() {
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    public init(timestamp: UInt64) {
        self.timestamp = timestamp
    }
}

/// Client → Server: request quality change based on network conditions.
public struct QualityUpdate: Codable, Sendable {
    public let requestedBitrate: Int
    public let requestedFPS: Int

    public init(requestedBitrate: Int, requestedFPS: Int) {
        self.requestedBitrate = requestedBitrate
        self.requestedFPS = requestedFPS
    }
}
