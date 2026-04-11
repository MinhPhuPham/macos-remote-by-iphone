import Foundation
import CoreGraphics

/// Injects mouse events into macOS via CGEvent.
final class MouseInjector {

    /// Check if Accessibility permission is granted (required for CGEvent injection).
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event Injection

    func inject(event: MouseEvent) {
        let point = CGPoint(x: event.x, y: event.y)

        let cgEventType: CGEventType
        let mouseButton: CGMouseButton

        switch event.type {
        case .move:
            cgEventType = .mouseMoved
            mouseButton = .left
        case .leftDown:
            cgEventType = .leftMouseDown
            mouseButton = .left
        case .leftUp:
            cgEventType = .leftMouseUp
            mouseButton = .left
        case .rightDown:
            cgEventType = .rightMouseDown
            mouseButton = .right
        case .rightUp:
            cgEventType = .rightMouseUp
            mouseButton = .right
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: cgEventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }

        cgEvent.post(tap: .cghidEventTap)
    }

    func click(at point: CGPoint) {
        injectRaw(type: .leftMouseDown, point: point, button: .left)
        injectRaw(type: .leftMouseUp, point: point, button: .left)
    }

    func doubleClick(at point: CGPoint) {
        if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: point, mouseButton: .left) {
            down1.setIntegerValueField(.mouseEventClickState, value: 1)
            down1.post(tap: .cghidEventTap)
        }
        if let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                              mouseCursorPosition: point, mouseButton: .left) {
            up1.setIntegerValueField(.mouseEventClickState, value: 1)
            up1.post(tap: .cghidEventTap)
        }
        if let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: point, mouseButton: .left) {
            down2.setIntegerValueField(.mouseEventClickState, value: 2)
            down2.post(tap: .cghidEventTap)
        }
        if let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                              mouseCursorPosition: point, mouseButton: .left) {
            up2.setIntegerValueField(.mouseEventClickState, value: 2)
            up2.post(tap: .cghidEventTap)
        }
    }

    func rightClick(at point: CGPoint) {
        injectRaw(type: .rightMouseDown, point: point, button: .right)
        injectRaw(type: .rightMouseUp, point: point, button: .right)
    }

    func scroll(deltaX: Int32, deltaY: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                   units: .pixel,
                                   wheelCount: 2,
                                   wheel1: deltaY,
                                   wheel2: deltaX,
                                   wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    func moveCursor(to point: CGPoint) {
        injectRaw(type: .mouseMoved, point: point, button: .left)
    }

    func drag(to point: CGPoint) {
        injectRaw(type: .leftMouseDragged, point: point, button: .left)
    }

    private func injectRaw(type: CGEventType, point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                   mouseCursorPosition: point, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }
}
