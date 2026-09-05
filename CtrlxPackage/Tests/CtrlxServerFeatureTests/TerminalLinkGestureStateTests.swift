#if os(macOS)
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Terminal link gesture state")
    struct TerminalLinkGestureStateTests {
        @Test("A single click without a drag may activate a link")
        func singleClick() {
            var state = TerminalLinkGestureState()

            let cancelsPending = state.mouseDown(clickCount: 1)
            let activatesLink = state.mouseUp(clickCount: 1)

            #expect(!cancelsPending)
            #expect(activatesLink)
        }

        @Test("A drag never activates a link and resets for the next gesture")
        func dragSelection() {
            var state = TerminalLinkGestureState()

            _ = state.mouseDown(clickCount: 1)
            state.mouseDragged()
            let activatesDraggedLink = state.mouseUp(clickCount: 1)
            #expect(!activatesDraggedLink)
            #expect(!state.didDrag)

            _ = state.mouseDown(clickCount: 1)
            let activatesNextLink = state.mouseUp(clickCount: 1)
            #expect(activatesNextLink)
        }

        @Test(
            "Multi-click selection cancels the staged first click",
            arguments: [2, 3]
        )
        func multiClick(clickCount: Int) {
            var state = TerminalLinkGestureState()

            _ = state.mouseDown(clickCount: 1)
            let stagesFirstClick = state.mouseUp(clickCount: 1)
            let cancelsFirstClick = state.mouseDown(clickCount: clickCount)
            let activatesMultiClick = state.mouseUp(clickCount: clickCount)

            #expect(stagesFirstClick)
            #expect(cancelsFirstClick)
            #expect(!activatesMultiClick)
        }
    }
#endif
