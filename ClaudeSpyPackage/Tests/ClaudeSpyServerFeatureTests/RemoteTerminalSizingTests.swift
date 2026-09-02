#if os(macOS)
    import AppKit
    import Testing
    @testable import ClaudeSpyServerFeature

    @MainActor
    struct RemoteTerminalSizingTests {
        @Test("Locked host dimensions survive viewer layout changes")
        func hostDimensionsRemainLocked() {
            let view = InteractiveTerminalView(
                frame: NSRect(x: 0, y: 0, width: 800, height: 600)
            )
            let expectedColumns = 132
            let expectedRows = 48

            view.lockedDimensions = (cols: expectedColumns, rows: expectedRows)
            view.getTerminal().resize(cols: expectedColumns, rows: expectedRows)
            let optimalSize = view.getOptimalFrameSize().size
            view.setTerminalSize(optimalSize)

            view.frame.size.height = optimalSize.height * 2
            view.layoutSubtreeIfNeeded()

            #expect(view.getTerminal().cols == expectedColumns)
            #expect(view.getTerminal().rows == expectedRows)
            #expect(view.terminalView.frame.height == optimalSize.height)
            #expect(view.terminalView.frame.maxY == view.bounds.maxY)

            // Even if AppKit asks SwiftTerm itself to adopt the viewer height,
            // its delegate must restore the host pane dimensions immediately.
            view.terminalView.setFrameSize(
                NSSize(width: optimalSize.width, height: optimalSize.height * 2)
            )
            #expect(view.getTerminal().cols == expectedColumns)
            #expect(view.getTerminal().rows == expectedRows)
        }

        @Test("Overflowing host terminal keeps its final row visible")
        func overflowingTerminalIsBottomAligned() {
            let view = InteractiveTerminalView(
                frame: NSRect(x: 0, y: 0, width: 800, height: 600)
            )
            let expectedColumns = 111
            let expectedRows = 66

            view.lockedDimensions = (cols: expectedColumns, rows: expectedRows)
            view.getTerminal().resize(cols: expectedColumns, rows: expectedRows)
            let optimalSize = view.getOptimalFrameSize().size

            // Reproduce a viewer that is just short of the host's fixed grid.
            view.frame.size.height = optimalSize.height - 1
            view.setTerminalSize(optimalSize)
            view.layoutSubtreeIfNeeded()

            #expect(view.getTerminal().cols == expectedColumns)
            #expect(view.getTerminal().rows == expectedRows)
            #expect(view.terminalView.frame.height == optimalSize.height)
            #expect(view.terminalView.frame.minY == view.bounds.minY)
            #expect(view.terminalView.frame.maxY > view.bounds.maxY)
        }
    }
#endif
