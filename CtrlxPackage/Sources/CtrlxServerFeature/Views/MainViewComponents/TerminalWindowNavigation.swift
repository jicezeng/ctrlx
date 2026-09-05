/// Pure selection rules for macOS terminal-window shortcuts.
///
/// The visible tab strip owns ordering. This helper only filters that order to
/// live tmux windows on the primary side and chooses a target; it deliberately
/// knows nothing about local/remote transport or SwiftUI state.
enum TerminalWindowNavigation {
    static func orderedWindowIDs(
        liveWindowIDs: [String],
        storedTabOrder: [TabDragPayload],
        excludedWindowIDs: Set<String>
    ) -> [String] {
        TabDragPayload.reconciledOrder(
            windowIds: liveWindowIDs,
            fileTabIds: [],
            browserTabIds: [],
            storedOrder: storedTabOrder,
            includeFileExplorer: false,
            includeGit: false
        ).compactMap { payload in
            guard case let .window(id) = payload, !excludedWindowIDs.contains(id) else { return nil }
            return id
        }
    }

    static func adjacentWindowID(
        currentID: String?,
        orderedWindowIDs: [String],
        direction: Int
    ) -> String? {
        guard orderedWindowIDs.count > 1, direction != 0 else { return nil }
        guard
            let currentID,
            let currentIndex = orderedWindowIDs.firstIndex(of: currentID)
        else {
            return direction > 0 ? orderedWindowIDs.first : orderedWindowIDs.last
        }

        let step = direction > 0 ? 1 : -1
        let targetIndex = (currentIndex + step + orderedWindowIDs.count) % orderedWindowIDs.count
        return orderedWindowIDs[targetIndex]
    }

    static func windowID(at index: Int, orderedWindowIDs: [String]) -> String? {
        guard orderedWindowIDs.indices.contains(index) else { return nil }
        return orderedWindowIDs[index]
    }
}
