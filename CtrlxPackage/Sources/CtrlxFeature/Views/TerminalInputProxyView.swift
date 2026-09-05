import Foundation

/// The terminal operations needed to make one editable shadow document match
/// another. Deletions are counted in grapheme clusters because one terminal
/// Backspace removes one user-visible character, not one UTF-16 code unit.
struct TerminalInputDocumentDelta: Equatable {
    let deletionCount: Int
    let insertion: String
}

/// Tracks the text already forwarded to the terminal and computes the smallest
/// end-of-line edit for a new native text document.
struct TerminalInputDocumentSynchronizer {
    private(set) var forwardedText = ""

    mutating func advance(to text: String) -> TerminalInputDocumentDelta {
        var oldIndex = forwardedText.startIndex
        var newIndex = text.startIndex

        while
            oldIndex < forwardedText.endIndex,
            newIndex < text.endIndex,
            forwardedText[oldIndex] == text[newIndex] {
            forwardedText.formIndex(after: &oldIndex)
            text.formIndex(after: &newIndex)
        }

        let delta = TerminalInputDocumentDelta(
            deletionCount: forwardedText[oldIndex...].count,
            insertion: String(text[newIndex...])
        )
        forwardedText = text
        return delta
    }

    mutating func reset() {
        forwardedText = ""
    }
}

#if os(iOS)
    import UIKit

    /// A native shadow editor for terminal keyboard input.
    ///
    /// Third-party keyboards read back the document after every insertion. A
    /// hand-written documentless `UITextInput` cannot satisfy that contract:
    /// the keyboard inserts recognized speech, reads an unchanged document and
    /// eventually abandons the session. `UITextView` owns the full UIKit text
    /// protocol here; this class only forwards its committed delta to tmux.
    final class TerminalInputProxyView: UITextView, UITextViewDelegate {
        private static let anchor = "\u{200B}"
        private static let anchorLength = (anchor as NSString).length
        private static let debugEnabled = ProcessInfo.processInfo.environment["CTRLX_TEXT_INPUT_DEBUG"] == "1"

        var onInsertText: ((String) -> Void)?
        var onDeleteBackward: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        var inputAccessoryViewProvider: (() -> UIView?)?
        var inputViewProvider: (() -> UIView?)?
        weak var forwardedNextResponder: UIResponder?

        var inputEnabled = false

        private var synchronizer = TerminalInputDocumentSynchronizer()
        private var isApplyingInternalEdit = false
        private var assignedInputAccessoryView: UIView?
        private var assignedInputView: UIView?

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            configureEditor()
        }

        convenience init(frame: CGRect) {
            self.init(frame: frame, textContainer: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var canBecomeFirstResponder: Bool {
            inputEnabled
        }

        /// The proxy is a sibling overlay of the terminal so it stays fixed in
        /// the visible viewport. Preserve the terminal's responder chain for
        /// hardware key commands that the native editor does not consume.
        override var next: UIResponder? {
            forwardedNextResponder ?? super.next
        }

        override var inputAccessoryView: UIView? {
            get { inputAccessoryViewProvider?() ?? assignedInputAccessoryView }
            set { assignedInputAccessoryView = newValue }
        }

        override var inputView: UIView? {
            get { inputViewProvider?() ?? assignedInputView }
            set { assignedInputView = newValue }
        }

        /// The proxy covers the terminal so UIKit can lay out a real document,
        /// but all touches must continue to reach the visible terminal view.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }

        override func becomeFirstResponder() -> Bool {
            let becameFirstResponder = super.becomeFirstResponder()
            if becameFirstResponder {
                trace("focus became-first-responder mode=\(textInputMode?.primaryLanguage ?? "unknown")")
                onFocusChange?(true)
            }
            return becameFirstResponder
        }

        override func resignFirstResponder() -> Bool {
            let resignedFirstResponder = super.resignFirstResponder()
            if resignedFirstResponder {
                trace("focus resigned-first-responder")
                onFocusChange?(false)
            }
            return resignedFirstResponder
        }

        func textViewDidChange(_: UITextView) {
            synchronizeCommittedDocument()
        }

        func textViewDidChangeSelection(_: UITextView) {
            // Committing marked text can change only the selection/marked state,
            // not the underlying characters. Observe both delegate callbacks so
            // an IME candidate is forwarded exactly when it becomes committed.
            synchronizeCommittedDocument()
        }

        private func synchronizeCommittedDocument() {
            guard !isApplyingInternalEdit else { return }
            restoreAnchorIfNeeded()

            // An IME owns marked text until it commits. Forwarding provisional
            // pinyin/candidates would duplicate or corrupt the remote input line.
            guard markedTextRange == nil else {
                trace("marked document utf16=\(payload.utf16.count)")
                return
            }

            let committedText = payload
            let delta = synchronizer.advance(to: committedText)
            guard delta.deletionCount > 0 || !delta.insertion.isEmpty else { return }
            trace(
                "document utf16=\(committedText.utf16.count) " +
                    "delete=\(delta.deletionCount) insert=\(delta.insertion.debugDescription)"
            )

            for _ in 0..<delta.deletionCount {
                onDeleteBackward?()
            }
            if !delta.insertion.isEmpty {
                onInsertText?(delta.insertion)
            }

            // Return starts a new terminal input line. The remote command has
            // already received the newline, so reset only the local context.
            if committedText.contains("\n") || committedText.contains("\r") {
                resetDocument()
            }
        }

        func textView(
            _: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard range.location < Self.anchorLength else { return true }

            // Preserve the invisible anchor at an otherwise empty input line so
            // software-keyboard Backspace continues to reach the terminal.
            if text.isEmpty, payload.isEmpty {
                onDeleteBackward?()
            }
            return false
        }

        private var payload: String {
            guard text.hasPrefix(Self.anchor) else { return text }
            return String(text.dropFirst())
        }

        private func configureEditor() {
            delegate = self
            backgroundColor = .clear
            textColor = .clear
            tintColor = .clear
            isAccessibilityElement = false
            isScrollEnabled = true
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            autocorrectionType = .no
            autocapitalizationType = .none
            spellCheckingType = .no
            smartQuotesType = .no
            smartDashesType = .no
            smartInsertDeleteType = .no
            textContainerInset = .zero
            textContainer.lineFragmentPadding = 0
            inputAssistantItem.leadingBarButtonGroups = []
            inputAssistantItem.trailingBarButtonGroups = []
            resetDocument()
        }

        private func restoreAnchorIfNeeded() {
            guard !text.hasPrefix(Self.anchor) else { return }
            let originalText = text ?? ""
            let originalSelection = selectedRange
            isApplyingInternalEdit = true
            text = Self.anchor + originalText
            selectedRange = NSRange(
                location: originalSelection.location + Self.anchorLength,
                length: originalSelection.length
            )
            isApplyingInternalEdit = false
        }

        private func resetDocument() {
            isApplyingInternalEdit = true
            text = Self.anchor
            selectedRange = NSRange(location: Self.anchorLength, length: 0)
            synchronizer.reset()
            isApplyingInternalEdit = false
        }

        private func trace(_ message: @autoclosure () -> String) {
            guard Self.debugEnabled else { return }
            print("[GallagerTextInput] \(message())")
        }
    }
#endif
