import Foundation

/// Single source of truth for app-wide identifiers.
/// Keychain service names are intentionally kept stable — changing them
/// would orphan previously stored credentials.
enum AppConstants {
    /// Logger subsystem — matches the bundle identifier for Console.app filtering.
    static let subsystem = "com.jable-johnson.JPMacIPIOSControl"

    /// Keychain service name for device identity.
    /// Do NOT change — existing stored UUIDs use this key.
    static let keychainService = "com.myremote.client"

    /// Dispatch queue label prefix.
    static let queuePrefix = "com.jable-johnson.JPMacIPIOSControl"
}
