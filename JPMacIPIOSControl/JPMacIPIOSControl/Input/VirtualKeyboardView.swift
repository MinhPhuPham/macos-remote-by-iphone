import JPMacIPRemoteShared
import SwiftUI
import UIKit

/// A hidden UITextField that captures iOS keyboard input and forwards it as key events.
struct VirtualKeyboardView: UIViewRepresentable {

    @Binding var isActive: Bool
    let onKeyPress: (String, UInt16, Bool) -> Void  // (character, keyCode, isSpecialKey)

    func makeUIView(context: Context) -> KeyCaptureTextField {
        let field = KeyCaptureTextField()
        field.keyPressHandler = onKeyPress
        field.alpha = 0.01
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.accessibilityLabel = "Text input for remote keyboard"
        return field
    }

    func updateUIView(_ uiView: KeyCaptureTextField, context: Context) {
        if isActive && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isActive && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: KeyCaptureTextField, coordinator: ()) {
        uiView.resignFirstResponder()
    }
}

/// Custom UITextField that intercepts every keystroke for forwarding to the server.
final class KeyCaptureTextField: UITextField, UITextFieldDelegate {

    var keyPressHandler: ((String, UInt16, Bool) -> Void)?

    // Cached key commands — computed once, not on every UIKit query.
    private lazy var cachedKeyCommands: [UIKeyCommand] = {
        var commands: [UIKeyCommand] = []

        let arrowKeys: [(String, String)] = [
            (UIKeyCommand.inputUpArrow, "up"),
            (UIKeyCommand.inputDownArrow, "down"),
            (UIKeyCommand.inputLeftArrow, "left"),
            (UIKeyCommand.inputRightArrow, "right"),
        ]
        for (input, name) in arrowKeys {
            let cmd = UIKeyCommand(input: input, modifierFlags: [], action: #selector(handleArrowKey))
            cmd.title = name
            commands.append(cmd)
        }

        commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)))
        commands.append(UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)))

        return commands
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        text = " "
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
        text = " "
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty {
            if let keyCode = KeyCodeMap.specialKeyToKeyCode["delete"] {
                keyPressHandler?("delete", keyCode, true)
            }
        } else {
            for char in string {
                let charStr = String(char)
                if let keyCode = KeyCodeMap.keyCode(for: charStr) {
                    keyPressHandler?(charStr, keyCode, false)
                }
            }
        }

        DispatchQueue.main.async {
            textField.text = " "
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let keyCode = KeyCodeMap.specialKeyToKeyCode["return"] {
            keyPressHandler?("return", keyCode, true)
        }
        return false
    }

    // MARK: - Hardware Keyboard Support

    override var keyCommands: [UIKeyCommand]? { cachedKeyCommands }

    @objc private func handleArrowKey(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        let name: String
        switch input {
        case UIKeyCommand.inputUpArrow:    name = "up"
        case UIKeyCommand.inputDownArrow:  name = "down"
        case UIKeyCommand.inputLeftArrow:  name = "left"
        case UIKeyCommand.inputRightArrow: name = "right"
        default: return
        }
        if let keyCode = KeyCodeMap.specialKeyToKeyCode[name] {
            keyPressHandler?(name, keyCode, true)
        }
    }

    @objc private func handleEscape(_ command: UIKeyCommand) {
        if let keyCode = KeyCodeMap.specialKeyToKeyCode["escape"] {
            keyPressHandler?("escape", keyCode, true)
        }
    }

    @objc private func handleTab(_ command: UIKeyCommand) {
        if let keyCode = KeyCodeMap.specialKeyToKeyCode["tab"] {
            keyPressHandler?("tab", keyCode, true)
        }
    }
}
