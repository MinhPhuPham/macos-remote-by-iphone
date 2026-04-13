import CoreGraphics
import Foundation
import os

/// Injects keyboard events into macOS via CGEvent.
final class KeyboardInjector {

    // MARK: - Event Injection

    /// Inject a single key event (down or up).
    func inject(event: KeyEvent) {
        Log.input.debug("Key inject: code=\(event.keyCode) down=\(event.isDown)")
        let flags = CGEventFlags(rawValue: event.modifiers)
        injectKey(keyCode: event.keyCode, isDown: event.isDown, modifiers: flags)
    }

    /// Inject a key down + key up sequence (a single keypress).
    func press(keyCode: UInt16, modifiers: CGEventFlags = []) {
        injectKey(keyCode: keyCode, isDown: true, modifiers: modifiers)
        injectKey(keyCode: keyCode, isDown: false, modifiers: modifiers)
    }

    /// Type a string by mapping each character to key events.
    func typeString(_ string: String) {
        for char in string {
            let charStr = String(char).lowercased()
            guard let keyCode = KeyCodeMap.keyCode(for: charStr) else { continue }

            var modifiers: CGEventFlags = []
            if KeyCodeMap.requiresShift(char) {
                modifiers.insert(.maskShift)
            }

            press(keyCode: keyCode, modifiers: modifiers)
        }
    }

    // MARK: - Common Shortcuts

    /// Inject Cmd+C.
    func copy() {
        press(keyCode: 0x08, modifiers: .maskCommand) // c
    }

    /// Inject Cmd+V.
    func paste() {
        press(keyCode: 0x09, modifiers: .maskCommand) // v
    }

    /// Inject Cmd+Z.
    func undo() {
        press(keyCode: 0x06, modifiers: .maskCommand) // z
    }

    /// Inject Cmd+A.
    func selectAll() {
        press(keyCode: 0x00, modifiers: .maskCommand) // a
    }

    /// Inject Cmd+Tab.
    func appSwitcher() {
        press(keyCode: 0x30, modifiers: .maskCommand) // tab
    }

    // MARK: - Internal

    private func injectKey(keyCode: UInt16, isDown: Bool, modifiers: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil,
                                   virtualKey: keyCode,
                                   keyDown: isDown) else { return }
        event.flags = modifiers
        event.post(tap: .cghidEventTap)
    }
}
