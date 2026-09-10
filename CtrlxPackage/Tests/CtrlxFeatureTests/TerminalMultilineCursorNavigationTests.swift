import Testing
@testable import CtrlxFeature

@Suite("Multiline terminal cursor navigation")
struct TerminalMultilineCursorNavigationTests {
    private typealias Navigation = TerminalMultilineCursorNavigation
    private typealias Point = Navigation.Point

    @Test("A shaded prompt supports either direction and multiple visible rows", arguments: [1, 2, 3])
    func differentRows(row: Int) throws {
        let lines = draft()
        let cursor = Point(column: 4, row: row)
        let region = try #require(Navigation.region(lines: lines, cursor: cursor))
        #expect(region.rows == 1..<4)
        for targetRow in 1...3 where targetRow != row {
            let move = try #require(Navigation.PendingMove(
                lines: lines, cursor: cursor, tap: .init(column: 3, row: targetRow), displayRow: 100
            ))
            #expect(move.verticalSteps == targetRow - row)
            #expect(move.target == Point(column: 3, row: targetRow))
        }
    }

    @Test("Soft-wrapped and explicit-newline TUI rows need no inferred line break metadata")
    func visualLines() throws {
        let lines = [line("› abcdefghijklmn", shaded: true), line("  op", shaded: true)]
        let move = try #require(Navigation.PendingMove(
            lines: lines, cursor: .init(column: 4, row: 1),
            tap: .init(column: 8, row: 0), displayRow: 0
        ))
        #expect(move.verticalSteps == -1)
        #expect(move.progress(lines: lines, cursor: .init(column: 4, row: 0), displayRow: 0) == .horizontalSteps(4))
    }

    @Test("Body, footer and top/bottom padding are never navigation targets", arguments: [0, 4, 5, -1, 10])
    func outsideInput(row: Int) {
        #expect(Navigation.PendingMove(
            lines: draft(), cursor: .init(column: 5, row: 2),
            tap: .init(column: 3, row: row), displayRow: 0
        ) == nil)
    }

    @Test("A background or a prompt alone does not identify a multiline editor")
    func unboundedOutput() {
        #expect(Navigation.region(lines: [line("body", shaded: true), line("  output", shaded: true)],
                                  cursor: .init(column: 4, row: 1)) == nil)
        #expect(Navigation.region(lines: [line("> prompt"), line("  output")],
                                  cursor: .init(column: 4, row: 1)) == nil)
        #expect(Navigation.region(lines: [line("  > quote", shaded: true), line("not a draft", shaded: true)],
                                  cursor: .init(column: 4, row: 1)) == nil)
    }

    @Test("A pair of borders can delimit an unshaded prompt without selecting output")
    func borderedPrompt() throws {
        let lines = [line("────────────────"), line("❯ hello"), line("  world"), line("────────────────"), line("footer")]
        let region = try #require(Navigation.region(lines: lines, cursor: .init(column: 3, row: 2)))
        #expect(region.rows == 1..<3)
        #expect(Navigation.region(lines: Array(lines.dropLast(2)), cursor: .init(column: 3, row: 2)) == nil)
        #expect(Navigation.region(lines: Array(lines.dropFirst()), cursor: .init(column: 3, row: 1)) == nil)
    }

    @Test("Two independent prompts cannot be joined into one editor")
    func separatePrompts() {
        let lines = [line("› first", shaded: true), line("› second", shaded: true)]
        #expect(Navigation.region(lines: lines, cursor: .init(column: 4, row: 1)) == nil)
    }

    @Test("Internal empty lines remain editable, trailing padding does not")
    func blankLine() throws {
        let lines = [line("› first", shaded: true), line("", shaded: true), line("  last", shaded: true), line("", shaded: true)]
        let region = try #require(Navigation.region(lines: lines, cursor: .init(column: 4, row: 2)))
        #expect(region.target(.init(column: 10, row: 1)) == Point(column: 2, row: 1))
        #expect(region.target(.init(column: 10, row: 3)) == nil)
    }

    @Test("An empty last input line containing the cursor is retained")
    func emptyCursorRow() throws {
        let lines = [line("› first", shaded: true), line("", shaded: true), line("", shaded: true)]
        let region = try #require(Navigation.region(lines: lines, cursor: .init(column: 2, row: 1)))
        #expect(region.rows == 0..<2)
    }

    @Test("Prompt gutter and short-line whitespace clamp inside the target line")
    func clampsColumns() throws {
        let region = try #require(Navigation.region(lines: draft(), cursor: .init(column: 5, row: 2)))
        #expect(region.target(.init(column: 0, row: 1)) == Point(column: 2, row: 1))
        #expect(region.target(.init(column: 200, row: 3)) == Point(column: 4, row: 3))
    }

    @Test("Wide glyph halves and emoji are single cursor steps")
    func wideCells() throws {
        let lines = [line("› abc", shaded: true), line("  中🙂é", shaded: true)]
        let move = try #require(Navigation.PendingMove(
            lines: lines, cursor: .init(column: 5, row: 0),
            tap: .init(column: 3, row: 1), displayRow: 0
        ))
        #expect(move.target.column == 2)
        #expect(move.progress(lines: lines, cursor: .init(column: 7, row: 1), displayRow: 0) == .horizontalSteps(-3))
    }

    @Test("Horizontal correction uses the returned cursor, not the previous preferred column", arguments: [2, 4, 7])
    func actualColumn(column: Int) throws {
        let lines = draft()
        let move = try #require(Navigation.PendingMove(
            lines: lines, cursor: .init(column: 3, row: 3),
            tap: .init(column: 6, row: 1), displayRow: 100
        ))
        #expect(move.progress(lines: lines, cursor: .init(column: column, row: 1), displayRow: 100) == .horizontalSteps(6 - column))
        #expect(move.progress(lines: lines, cursor: .init(column: 4, row: 2), displayRow: 100) == .waiting)
    }

    @Test("Feedback arriving after expiry, scrolling, editing or leaving the draft is cancelled")
    func staleFeedback() throws {
        let now = ContinuousClock.now
        let lines = draft()
        let move = try #require(Navigation.PendingMove(
            lines: lines, cursor: .init(column: 4, row: 1),
            tap: .init(column: 3, row: 3), displayRow: 100, now: now
        ))
        #expect(move.progress(lines: lines, cursor: .init(column: 4, row: 1), displayRow: 100, now: now) == .waiting)
        #expect(move.progress(lines: lines, cursor: move.target, displayRow: 100, now: now.advanced(by: .seconds(2))) == .cancelled)
        #expect(move.progress(lines: lines, cursor: move.target, displayRow: 99) == .cancelled)
        #expect(move.progress(lines: lines, cursor: .init(column: 5, row: 5), displayRow: 100) == .cancelled)
        var edited = lines
        edited[2] = line("  new input", shaded: true)
        #expect(move.progress(lines: edited, cursor: move.target, displayRow: 100) == .cancelled)
        #expect(move.progress(lines: Array(lines.prefix(2)), cursor: move.target, displayRow: 100) == .cancelled)
    }

    @Test("Same-row taps remain on the old path")
    func sameRow() {
        #expect(Navigation.PendingMove(
            lines: draft(), cursor: .init(column: 4, row: 1),
            tap: .init(column: 6, row: 1), displayRow: 0
        ) == nil)
    }

    private func draft() -> [Navigation.Line] {
        [line("body"), line("› first line", shaded: true), line("  second", shaded: true),
         line("  hi", shaded: true), line("", shaded: true), line("footer")]
    }

    private func line(_ text: String, shaded: Bool = false) -> Navigation.Line {
        var cells: [Navigation.Cell] = []
        for character in text {
            let width = "中🙂".contains(character) ? 2 : 1
            cells.append(.init(character: character, width: width, inputBackground: shaded))
            if width == 2 { cells.append(.init(character: "\0", width: 0, inputBackground: shaded)) }
        }
        while cells.count < 16 { cells.append(.init(character: " ", width: 1, inputBackground: shaded)) }
        return .init(cells: cells)
    }
}
