#if os(macOS)
    import AppKit
    import Testing
    @testable import CtrlxServerFeature

    @MainActor
    struct RemoteTerminalSizingTests {
        @Test("Height-only pane changes are not deduplicated")
        func heightOnlyChangeIsObserved() {
            var tracker = TerminalDimensionChangeTracker()
            let initialChange = tracker.record(width: 225, height: 24)
            let heightChange = tracker.record(width: 225, height: 66)

            #expect(initialChange)
            #expect(heightChange)
        }

        @Test("Identical pane dimensions are deduplicated")
        func identicalDimensionsAreIgnored() {
            var tracker = TerminalDimensionChangeTracker()
            let initialChange = tracker.record(width: 225, height: 66)
            let duplicateChange = tracker.record(width: 225, height: 66)

            #expect(initialChange)
            #expect(!duplicateChange)
        }

        @Test("A height-only change creates one shared resync boundary")
        func heightChangeCreatesSharedResyncBoundary() throws {
            let first = UUID()
            let second = UUID()
            let boundary = try #require(PaneDimensionResyncBoundary(
                currentWidth: 225,
                currentHeight: 61,
                newWidth: 225,
                newHeight: 66,
                subscriptionIds: [first, second]
            ))

            #expect(boundary.width == 225)
            #expect(boundary.height == 66)
            #expect(boundary.subscriptionIds == [first, second])
        }

        @Test("An identical pane size creates no resync boundary")
        func duplicateSizeCreatesNoResyncBoundary() {
            let boundary = PaneDimensionResyncBoundary(
                currentWidth: 225,
                currentHeight: 66,
                newWidth: 225,
                newHeight: 66,
                subscriptionIds: [UUID()]
            )

            #expect(boundary == nil)
        }

        @Test("A request arriving during capture is retained for the next round")
        func requestDuringCaptureStartsAnotherRound() {
            let subscriber = UUID()
            var requests = PaneResyncRequestQueue()

            requests.request(paneId: "%6", subscriptionIds: [subscriber])
            #expect(requests.take(paneId: "%6") == [subscriber])

            // The first round is now capturing. The same ID must not merge
            // backward into the already-consumed round.
            requests.request(paneId: "%6", subscriptionIds: [subscriber])
            #expect(requests.hasRequests(paneId: "%6"))
            #expect(requests.take(paneId: "%6") == [subscriber])
            #expect(!requests.hasRequests(paneId: "%6"))
        }

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
