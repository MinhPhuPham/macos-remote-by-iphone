import os

/// Centralized loggers for the Mac server.
/// Usage: `Log.network.info("Listening on port \(port)")`
///
/// Filter in Console.app: subsystem = "com.jable-johnson.JPMacIPMacServer"
enum Log {
    static let app        = Logger(subsystem: AppConstants.subsystem, category: "App")
    static let auth       = Logger(subsystem: AppConstants.subsystem, category: "Auth")
    static let network    = Logger(subsystem: AppConstants.subsystem, category: "Network")
    static let bonjour    = Logger(subsystem: AppConstants.subsystem, category: "Bonjour")
    static let connection = Logger(subsystem: AppConstants.subsystem, category: "Connection")
    static let pairing    = Logger(subsystem: AppConstants.subsystem, category: "Pairing")
    static let capture    = Logger(subsystem: AppConstants.subsystem, category: "Capture")
    static let encoder    = Logger(subsystem: AppConstants.subsystem, category: "Encoder")
}
