import os

/// Centralized loggers for the iOS client.
///
/// Filter in Console.app:
///   subsystem = "com.jable-johnson.MacIOSRemoteApp"
///   category = "Connection" | "Video" | "Session" | "Input" | "Quality"
enum Log {
    static let app        = Logger(subsystem: AppConstants.subsystem, category: "App")
    static let connection = Logger(subsystem: AppConstants.subsystem, category: "Connection")
    static let video      = Logger(subsystem: AppConstants.subsystem, category: "Video")
    static let session    = Logger(subsystem: AppConstants.subsystem, category: "Session")
    static let input      = Logger(subsystem: AppConstants.subsystem, category: "Input")
    static let quality    = Logger(subsystem: AppConstants.subsystem, category: "Quality")
}
