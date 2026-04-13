import SwiftUI

/// Active modifier key flags matching CGEventFlags raw values.
struct ModifierKeys: OptionSet, Sendable {
    let rawValue: UInt64

    static let command  = ModifierKeys(rawValue: 1 << 20)
    static let option   = ModifierKeys(rawValue: 1 << 19)
    static let control  = ModifierKeys(rawValue: 1 << 18)
    static let shift    = ModifierKeys(rawValue: 1 << 17)
}

/// A bar of toggle buttons for Cmd, Opt, Ctrl, Shift modifier keys.
/// Modifiers are "sticky" — tap to activate, auto-deactivate after a keypress.
struct ModifierKeysBar: View {

    @Binding var activeModifiers: ModifierKeys
    let onKeyboardToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            modifierButton(label: "\u{2318}", modifier: .command, accessibilityLabel: "Command")
            modifierButton(label: "\u{2325}", modifier: .option, accessibilityLabel: "Option")
            modifierButton(label: "\u{2303}", modifier: .control, accessibilityLabel: "Control")
            modifierButton(label: "\u{21E7}", modifier: .shift, accessibilityLabel: "Shift")

            Spacer()

            Button(action: onKeyboardToggle) {
                Image(systemName: "keyboard")
                    .font(.title3)
                    .padding(8)
            }
            .accessibilityLabel("Toggle keyboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func modifierButton(label: String, modifier: ModifierKeys, accessibilityLabel: String) -> some View {
        let isActive = activeModifiers.contains(modifier)
        return Button {
            if isActive {
                activeModifiers.remove(modifier)
            } else {
                activeModifiers.insert(modifier)
            }
        } label: {
            Text(label)
                .font(.title2)
                .frame(width: 44, height: 44) // 44pt minimum tap target per HIG
                .background(isActive ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
