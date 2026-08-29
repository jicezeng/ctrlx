#if os(iOS)
    import ClaudeSpyNetworking
    import SwiftUI

    /// A dedicated terminal-input control that stays outside terminal content.
    struct TerminalKeyboardBar: View {
        let keyboardVisible: Bool
        let isEnabled: Bool
        let bottomSafeAreaInset: CGFloat
        let action: () -> Void
        let sendVoiceKeys: ([TmuxKey]) -> Void

        private var reclaimedBottomSafeArea: CGFloat {
            guard !keyboardVisible else { return 0 }
            return min(max(bottomSafeAreaInset, 0) / 2, 16)
        }

        var body: some View {
            HStack(spacing: 6) {
                Button(action: action) {
                    Label(
                        keyboardVisible ? "Hide Keyboard" : "Input",
                        symbol: keyboardVisible ? .keyboardChevronCompactDown : .keyboard
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .disabled(!isEnabled)
                .accessibilityIdentifier("terminal-keyboard-control")

                TerminalVoiceInputButton(
                    isDisabled: !isEnabled,
                    showsLabel: true,
                    sendKeys: sendVoiceKeys
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
            // Keep enough room for the Home Indicator while reclaiming part of
            // the otherwise empty safe area. A home-button device reports zero,
            // and the keyboard path never overlaps its own safe area.
            .padding(.bottom, -reclaimedBottomSafeArea)
        }
    }
#endif
