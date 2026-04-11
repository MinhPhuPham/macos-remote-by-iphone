import Foundation

/// Maps characters and key names to macOS virtual key codes (Carbon/Events.h values).
public enum KeyCodeMap {

    /// Character → virtual key code mapping for the standard US ANSI keyboard layout.
    public static let characterToKeyCode: [String: UInt16] = [
        // Row 1: number row
        "`": 0x32, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        "0": 0x1D, "-": 0x1B, "=": 0x18,

        // Row 2: QWERTY
        "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "t": 0x11,
        "y": 0x10, "u": 0x20, "i": 0x22, "o": 0x1F, "p": 0x23,
        "[": 0x21, "]": 0x1E, "\\": 0x2A,

        // Row 3: ASDF
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "g": 0x05,
        "h": 0x04, "j": 0x26, "k": 0x28, "l": 0x25, ";": 0x29,
        "'": 0x27,

        // Row 4: ZXCV
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B,
        "n": 0x2D, "m": 0x2E, ",": 0x2B, ".": 0x2F, "/": 0x2C,

        // Shifted symbols (same physical key, but mapped separately for lookup)
        "~": 0x32, "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15,
        "%": 0x17, "^": 0x16, "&": 0x1A, "*": 0x1C, "(": 0x19,
        ")": 0x1D, "_": 0x1B, "+": 0x18,
        "{": 0x21, "}": 0x1E, "|": 0x2A,
        ":": 0x29, "\"": 0x27,
        "<": 0x2B, ">": 0x2F, "?": 0x2C,

        // Space
        " ": 0x31,
    ]

    /// Named special keys → virtual key code.
    public static let specialKeyToKeyCode: [String: UInt16] = [
        "return":     0x24,
        "enter":      0x4C, // numpad enter
        "tab":        0x30,
        "space":      0x31,
        "delete":     0x33, // backspace
        "forwardDelete": 0x75,
        "escape":     0x35,
        "command":    0x37,
        "shift":      0x38,
        "capsLock":   0x39,
        "option":     0x3A,
        "control":    0x3B,
        "rightCommand": 0x36,
        "rightShift": 0x3C,
        "rightOption": 0x3D,
        "rightControl": 0x3E,
        "function":   0x3F,
        "f1":  0x7A, "f2":  0x78, "f3":  0x63, "f4":  0x76,
        "f5":  0x60, "f6":  0x61, "f7":  0x62, "f8":  0x64,
        "f9":  0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A,
        "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        "home":       0x73,
        "end":        0x77,
        "pageUp":     0x74,
        "pageDown":   0x79,
        "left":       0x7B,
        "right":      0x7C,
        "down":       0x7D,
        "up":         0x7E,
        "volumeUp":   0x48,
        "volumeDown": 0x49,
        "mute":       0x4A,
    ]

    /// Characters that require Shift to type on a US keyboard.
    public static let shiftedCharacters: Set<Character> = Set(
        "~!@#$%^&*()_+{}|:\"<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )

    /// Look up the virtual key code for a character string.
    /// Returns nil if the character is unknown.
    public static func keyCode(for character: String) -> UInt16? {
        let lower = character.lowercased()
        return characterToKeyCode[lower] ?? specialKeyToKeyCode[lower]
    }

    /// Returns true if the character requires the Shift modifier.
    public static func requiresShift(_ character: Character) -> Bool {
        shiftedCharacters.contains(character)
    }
}
