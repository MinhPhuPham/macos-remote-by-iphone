import os

/// Centralized loggers for the iOS client.
/// Usage: `Log.network.info("Connected to \(host)")`
///
/// Filter in Console.app: subsystem = "com.jable-johnson.JPMacIPIOSControl"
enum Log {
    static let app        = Logger(subsystem: AppConstants.subsystem, category: "App")
    static let network    = Logger(subsystem: AppConstants.subsystem, category: "Network")
    static let connection = Logger(subsystem: AppConstants.subsystem, category: "Connection")
    static let pairing    = Logger(subsystem: AppConstants.subsystem, category: "Pairing")
    static let video      = Logger(subsystem: AppConstants.subsystem, category: "Video")
    static let session    = Logger(subsystem: AppConstants.subsystem, category: "Session")
    static let quality    = Logger(subsystem: AppConstants.subsystem, category: "Quality")
}
