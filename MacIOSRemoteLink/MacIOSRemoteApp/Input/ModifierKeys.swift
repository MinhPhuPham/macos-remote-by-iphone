import Foundation

/// Active modifier key flags matching CGEventFlags raw values.
struct ModifierKeys: OptionSet, Sendable {
    let rawValue: UInt64

    static let command  = ModifierKeys(rawValue: 1 << 20)
    static let option   = ModifierKeys(rawValue: 1 << 19)
    static let control  = ModifierKeys(rawValue: 1 << 18)
    static let shift    = ModifierKeys(rawValue: 1 << 17)
}
