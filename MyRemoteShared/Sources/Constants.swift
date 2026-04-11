import Foundation

/// Shared constants for MyRemote protocol and networking.
public enum MyRemoteConstants {
    /// Default TCP port for the server (5910 to avoid VNC/5900 conflict).
    public static let defaultPort: UInt16 = 5910

    /// Bonjour service type.
    public static let bonjourServiceType = "_myremote._tcp"

    /// Bonjour service domain.
    public static let bonjourDomain = "local."

    /// Protocol version string advertised in Bonjour TXT record.
    public static let protocolVersion = "1.0"

    /// Session timeout after no input activity (seconds).
    public static let sessionTimeoutInterval: TimeInterval = 1800 // 30 minutes

    /// Maximum failed auth attempts before blocking.
    public static let maxFailedAuthAttempts = 5

    /// Duration to block a device after too many failed attempts (seconds).
    public static let authBlockDuration: TimeInterval = 300 // 5 minutes

    /// Session token length in bytes.
    public static let sessionTokenLength = 32 // 256 bits

    /// Keyframe interval (in frames).
    public static let keyFrameInterval: Int = 60

    /// Auto-reconnect maximum retries.
    public static let maxReconnectRetries = 5

    /// Auto-reconnect base delay in seconds.
    public static let reconnectBaseDelay: TimeInterval = 1.0

    // MARK: - Network Mode Presets

    /// LAN-optimized settings.
    public enum LAN {
        public static let heartbeatInterval: TimeInterval = 5.0
        public static let defaultBitrate: Int = 4_000_000
        public static let lowBitrate: Int = 2_000_000
        public static let highBitrate: Int = 6_000_000
        public static let defaultFrameRate: Int = 30
        public static let lowFrameRate: Int = 15
        public static let highRTTThreshold: Double = 100
        public static let lowRTTThreshold: Double = 50
    }

    /// WAN/Cellular-optimized settings (4G/5G).
    public enum WAN {
        public static let heartbeatInterval: TimeInterval = 15.0
        public static let defaultBitrate: Int = 1_500_000
        public static let lowBitrate: Int = 500_000
        public static let highBitrate: Int = 3_000_000
        public static let defaultFrameRate: Int = 24
        public static let lowFrameRate: Int = 10
        public static let highRTTThreshold: Double = 250
        public static let lowRTTThreshold: Double = 100
    }
}

/// Connection mode: LAN (local WiFi) or WAN (internet/cellular).
public enum ConnectionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case lan = "LAN"
    case wan = "WAN"

    public var id: String { rawValue }

    public var heartbeatInterval: TimeInterval {
        switch self {
        case .lan: return MyRemoteConstants.LAN.heartbeatInterval
        case .wan: return MyRemoteConstants.WAN.heartbeatInterval
        }
    }

    public var defaultBitrate: Int {
        switch self {
        case .lan: return MyRemoteConstants.LAN.defaultBitrate
        case .wan: return MyRemoteConstants.WAN.defaultBitrate
        }
    }

    public var lowBitrate: Int {
        switch self {
        case .lan: return MyRemoteConstants.LAN.lowBitrate
        case .wan: return MyRemoteConstants.WAN.lowBitrate
        }
    }

    public var highBitrate: Int {
        switch self {
        case .lan: return MyRemoteConstants.LAN.highBitrate
        case .wan: return MyRemoteConstants.WAN.highBitrate
        }
    }

    public var defaultFrameRate: Int {
        switch self {
        case .lan: return MyRemoteConstants.LAN.defaultFrameRate
        case .wan: return MyRemoteConstants.WAN.defaultFrameRate
        }
    }

    public var lowFrameRate: Int {
        switch self {
        case .lan: return MyRemoteConstants.LAN.lowFrameRate
        case .wan: return MyRemoteConstants.WAN.lowFrameRate
        }
    }

    public var highRTTThreshold: Double {
        switch self {
        case .lan: return MyRemoteConstants.LAN.highRTTThreshold
        case .wan: return MyRemoteConstants.WAN.highRTTThreshold
        }
    }

    public var lowRTTThreshold: Double {
        switch self {
        case .lan: return MyRemoteConstants.LAN.lowRTTThreshold
        case .wan: return MyRemoteConstants.WAN.lowRTTThreshold
        }
    }
}
