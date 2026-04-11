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

    /// Heartbeat interval in seconds.
    public static let heartbeatInterval: TimeInterval = 5.0

    /// Session timeout after no input activity (seconds).
    public static let sessionTimeoutInterval: TimeInterval = 1800 // 30 minutes

    /// Maximum failed auth attempts before blocking.
    public static let maxFailedAuthAttempts = 5

    /// Duration to block an IP after too many failed attempts (seconds).
    public static let authBlockDuration: TimeInterval = 300 // 5 minutes

    /// Session token length in bytes.
    public static let sessionTokenLength = 32 // 256 bits

    /// Default video bitrate in bits per second.
    public static let defaultBitrate: Int = 4_000_000

    /// Low quality bitrate.
    public static let lowBitrate: Int = 2_000_000

    /// High quality bitrate.
    public static let highBitrate: Int = 6_000_000

    /// Default frame rate.
    public static let defaultFrameRate: Int = 30

    /// Low frame rate for poor network conditions.
    public static let lowFrameRate: Int = 15

    /// Keyframe interval (in frames).
    public static let keyFrameInterval: Int = 60

    /// RTT threshold (ms) to trigger quality reduction.
    public static let highRTTThreshold: Double = 100

    /// RTT threshold (ms) to allow quality increase.
    public static let lowRTTThreshold: Double = 50

    /// Auto-reconnect maximum retries.
    public static let maxReconnectRetries = 5

    /// Auto-reconnect base delay in seconds.
    public static let reconnectBaseDelay: TimeInterval = 1.0
}
