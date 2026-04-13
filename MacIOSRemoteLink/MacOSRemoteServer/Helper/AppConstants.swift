import Foundation

/// Single source of truth for app-wide identifiers.
/// Keychain service names are intentionally kept stable — changing them
/// would orphan previously stored credentials.
enum AppConstants {
    /// Logger subsystem — matches the bundle identifier for Console.app filtering.
    static let subsystem = "com.jable-johnson.JPMacIPMacServer"

    /// Keychain service name for server passwords/tokens.
    /// Do NOT change — existing stored passwords use this key.
    static let keychainService = "com.myremote.server"

    /// Dispatch queue label prefix.
    static let queuePrefix = "com.jable-johnson.JPMacIPMacServer"
}
