import Testing
@testable import CtrlxServerFeature

@Suite("Terminal window navigation")
struct TerminalWindowNavigationTests {
    @Test("Window order follows the visible tab order while skipping non-terminal tabs")
    func followsVisibleWindowOrder() {
        let ordered = TerminalWindowNavigation.orderedWindowIDs(
            liveWindowIDs: ["w1", "w2", "w3"],
            storedTabOrder: [
                .window("w3"),
                .fileExplorer,
                .window("w1"),
                .git,
                .window("w2"),
            ],
            excludedWindowIDs: []
        )

        #expect(ordered == ["w3", "w1", "w2"])
    }

    @Test("Windows assigned to the right split are excluded")
    func excludesRightSplitWindows() {
        let ordered = TerminalWindowNavigation.orderedWindowIDs(
            liveWindowIDs: ["left-1", "right", "left-2"],
            storedTabOrder: [.window("left-2"), .window("right"), .window("left-1")],
            excludedWindowIDs: ["right"]
        )

        #expect(ordered == ["left-2", "left-1"])
    }

    @Test("New live windows append in live order and stale windows disappear")
    func reconcilesLiveWindows() {
        let ordered = TerminalWindowNavigation.orderedWindowIDs(
            liveWindowIDs: ["existing", "new"],
            storedTabOrder: [.window("gone"), .window("existing")],
            excludedWindowIDs: []
        )

        #expect(ordered == ["existing", "new"])
    }

    @Test("Adjacent selection wraps in both directions")
    func adjacentSelectionWraps() {
        let windows = ["w1", "w2", "w3"]

        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: "w3",
            orderedWindowIDs: windows,
            direction: 1
        ) == "w1")
        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: "w1",
            orderedWindowIDs: windows,
            direction: -1
        ) == "w3")
    }

    @Test("A missing current selection enters from the requested edge")
    func missingSelectionUsesDirection() {
        let windows = ["w1", "w2", "w3"]

        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: "gone",
            orderedWindowIDs: windows,
            direction: 1
        ) == "w1")
        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: nil,
            orderedWindowIDs: windows,
            direction: -1
        ) == "w3")
    }

    @Test("Adjacent selection is a no-op with fewer than two windows")
    func adjacentSelectionNeedsTwoWindows() {
        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: "w1",
            orderedWindowIDs: ["w1"],
            direction: 1
        ) == nil)
        #expect(TerminalWindowNavigation.adjacentWindowID(
            currentID: nil,
            orderedWindowIDs: [],
            direction: -1
        ) == nil)
    }

    @Test("Direct selection uses zero-based visual position and rejects invalid positions")
    func directSelectionChecksBounds() {
        let windows = ["w1", "w2", "w3"]

        #expect(TerminalWindowNavigation.windowID(at: 0, orderedWindowIDs: windows) == "w1")
        #expect(TerminalWindowNavigation.windowID(at: 2, orderedWindowIDs: windows) == "w3")
        #expect(TerminalWindowNavigation.windowID(at: -1, orderedWindowIDs: windows) == nil)
        #expect(TerminalWindowNavigation.windowID(at: 3, orderedWindowIDs: windows) == nil)
    }
}
