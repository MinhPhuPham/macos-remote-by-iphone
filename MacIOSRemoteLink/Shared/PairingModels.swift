import Foundation

// MARK: - Pairing Code Signaling Protocol

/// Registration request: Mac → Signaling Server.
public struct PairingRegistration: Codable, Sendable {
    /// 6-character pairing code displayed on the Mac.
    public let code: String
    /// Mac's public IP (auto-detected by the signaling server from the request).
    /// Can also be provided explicitly if the Mac knows its public IP.
    public let publicIP: String?
    /// Port the Mac is listening on.
    public let port: UInt16
    /// Server's hostname (for display purposes).
    public let hostname: String
    /// Protocol version.
    public let version: String

    public init(code: String, publicIP: String? = nil, port: UInt16, hostname: String) {
        self.code = code
        self.publicIP = publicIP
        self.port = port
        self.hostname = hostname
        self.version = MyRemoteConstants.protocolVersion
    }
}

/// Lookup response: Signaling Server → iPhone.
public struct PairingLookupResult: Codable, Sendable {
    public let found: Bool
    public let publicIP: String?
    public let port: UInt16?
    public let hostname: String?
    public let version: String?
    public let error: String?

    public init(found: Bool, publicIP: String? = nil, port: UInt16? = nil,
                hostname: String? = nil, version: String? = nil, error: String? = nil) {
        self.found = found
        self.publicIP = publicIP
        self.port = port
        self.hostname = hostname
        self.version = version
        self.error = error
    }
}

// MARK: - Pairing Code Generation

public enum PairingCodeGenerator {
    /// Characters used in pairing codes (uppercase letters + digits, no ambiguous chars).
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Generate a random 6-character pairing code.
    public static func generate() -> String {
        (0..<6).map { _ in String(alphabet.randomElement()!) }.joined()
    }

    /// Format a code for display: "ABC-123" style.
    public static func format(_ code: String) -> String {
        let clean = code.uppercased().filter { alphabet.contains($0) }
        guard clean.count == 6 else { return clean }
        let index = clean.index(clean.startIndex, offsetBy: 3)
        return "\(clean[..<index])-\(clean[index...])"
    }

    /// Parse user input back to a raw code.
    public static func parse(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
