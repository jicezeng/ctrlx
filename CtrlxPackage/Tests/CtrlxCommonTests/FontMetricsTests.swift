#if os(macOS)
    import AppKit
    import CtrlxCommon
    import SwiftTerm
    import Testing

    @MainActor
    struct FontMetricsTests {
        @Test(
            "Cell width matches SwiftTerm device-pixel rounding",
            arguments: Array(8...24)
        )
        func cellWidthMatchesSwiftTerm(fontSize: Int) {
            let font = NSFont(name: "SF Mono", size: CGFloat(fontSize))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
            let terminalView = TerminalView(frame: .zero, font: font)
            let columns = terminalView.getTerminal().cols
            let optimalWidth = terminalView.getOptimalFrameSize().width
            let expectedWidth = (
                optimalWidth - FontMetrics.swiftTermScrollerWidth
            ) / CGFloat(columns)

            let cellSize = FontMetrics.calculateCellSize(font: font)

            #expect(cellSize.width == expectedWidth)
        }

        @Test("Scroller width matches SwiftTerm's overlay scroller")
        func scrollerWidthMatchesSwiftTerm() {
            let expectedWidth = NSScroller.scrollerWidth(
                for: .regular,
                scrollerStyle: .overlay
            )

            #expect(FontMetrics.swiftTermScrollerWidth == expectedWidth)
        }
    }
#endif
