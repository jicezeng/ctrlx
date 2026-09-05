#if canImport(SwiftTerm)
    import Foundation
    import SwiftTerm

    /// An immutable copy of the text currently retained by a terminal buffer.
    ///
    /// The snapshot deliberately does not observe subsequent terminal output. A stable
    /// value lets iOS keep a user's selection in place while the live pane continues to run.
    struct TerminalTextSnapshot: Identifiable, Equatable {
        let id = UUID()
        let text: String

        @MainActor
        init?(terminal: Terminal) {
            var lineCount = 0
            var row = terminal.buffer.totalLinesTrimmed

            while terminal.getScrollInvariantLine(row: row) != nil {
                lineCount += 1
                row += 1
            }

            guard lineCount > 0 else { return nil }

            // SwiftTerm's selection exporter already knows which buffer rows are
            // soft-wrapped continuations. Reusing it preserves hard line breaks
            // and blank lines without turning every terminal-width wrap into a
            // newline or exposing BufferLine's internal isWrapped flag.
            var text = terminal.getText(
                start: Position(col: 0, row: 0),
                end: Position(col: terminal.cols, row: lineCount - 1)
            )

            while text.last?.isNewline == true {
                text.removeLast()
            }

            guard text.contains(where: { !$0.isWhitespace }) else { return nil }
            self.text = text
        }
    }
#endif
