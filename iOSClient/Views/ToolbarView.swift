import SwiftUI

/// Bottom toolbar with keyboard toggle, status info toggle, and disconnect button.
struct ToolbarView: View {

    @Binding var isKeyboardActive: Bool
    @Binding var showStatusBar: Bool
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                isKeyboardActive.toggle()
            } label: {
                Image(systemName: isKeyboardActive ? "keyboard.fill" : "keyboard")
                    .font(.title3)
            }
            .accessibilityLabel(isKeyboardActive ? "Hide keyboard" : "Show keyboard")

            Button {
                showStatusBar.toggle()
            } label: {
                Image(systemName: showStatusBar ? "info.circle.fill" : "info.circle")
                    .font(.title3)
            }
            .accessibilityLabel(showStatusBar ? "Hide status bar" : "Show status bar")

            Spacer()

            Button(role: .destructive) {
                onDisconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Disconnect")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
