import os

/// Centralized loggers for the Mac server.
///
/// Filter in Console.app:
///   subsystem = "com.jable-johnson.MacIOSRemoteLink"
///   category = "App" | "Auth" | "Bonjour" | "Connection" | "Capture" | "Encoder" | "Input"
enum Log {
    static let app        = Logger(subsystem: AppConstants.subsystem, category: "App")
    static let auth       = Logger(subsystem: AppConstants.subsystem, category: "Auth")
    static let bonjour    = Logger(subsystem: AppConstants.subsystem, category: "Bonjour")
    static let connection = Logger(subsystem: AppConstants.subsystem, category: "Connection")
    static let capture    = Logger(subsystem: AppConstants.subsystem, category: "Capture")
    static let encoder    = Logger(subsystem: AppConstants.subsystem, category: "Encoder")
    static let input      = Logger(subsystem: AppConstants.subsystem, category: "Input")
}
