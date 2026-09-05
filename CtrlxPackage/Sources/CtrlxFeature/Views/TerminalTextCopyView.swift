#if os(iOS)
    import CtrlxCommon
    import Dependencies
    import SwiftUI
    import UIKit

    /// Presents an immutable terminal snapshot using UIKit's native text selection.
    struct TerminalTextCopyView: View {
        let snapshot: TerminalTextSnapshot

        @Environment(\.dismiss) private var dismiss
        @Dependency(ClipboardClient.self) private var clipboard

        var body: some View {
            NavigationStack {
                SelectableTerminalTextView(text: snapshot.text)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Terminal Text")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                clipboard.setString(snapshot.text)
                            } label: {
                                Label("Copy All", symbol: .docOnClipboard)
                            }
                        }
                    }
            }
        }
    }

    /// A read-only `UITextView` gives long terminal text the standard iOS selection handles,
    /// context menu, magnifier, and edge auto-scrolling behavior.
    private struct SelectableTerminalTextView: UIViewRepresentable {
        let text: String

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            let baseFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

            textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
            textView.adjustsFontForContentSizeCategory = true
            textView.backgroundColor = .systemBackground
            textView.textColor = .label
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = true
            textView.alwaysBounceVertical = true
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
            textView.textContainer.lineFragmentPadding = 0
            textView.accessibilityLabel = "Terminal text"
            textView.text = text
            return textView
        }

        func updateUIView(_ textView: UITextView, context _: Context) {
            guard textView.text != text else { return }
            textView.text = text
        }
    }
#endif
