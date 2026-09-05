import Foundation

/// Viewer-local ordering for paired remote hosts.
public enum RemoteHostOrder {
    /// Applies SwiftUI's `onMove` coordinates without depending on SwiftUI.
    public static func moving<Element>(
        _ elements: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Element] {
        let validSource = source.filter(elements.indices.contains).sorted()
        guard !validSource.isEmpty else { return elements }

        let moved = validSource.map { elements[$0] }
        let sourceSet = Set(validSource)
        var remaining = elements.enumerated().compactMap { index, element in
            sourceSet.contains(index) ? nil : element
        }
        let removedBeforeDestination = validSource.count { $0 < destination }
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), remaining.count)
        remaining.insert(contentsOf: moved, at: insertionIndex)
        return remaining
    }

    /// Moves one element to the target element's original position.
    ///
    /// This matches drag-and-drop intent in both directions: dropping a lower
    /// element on an upper target places it before the target, while dropping
    /// an upper element on a lower target places it after the target.
    public static func moving<Element>(
        _ elements: [Element],
        sourceID: String,
        targetID: String,
        id: (Element) -> String
    ) -> [Element] {
        guard
            sourceID != targetID,
            let sourceIndex = elements.firstIndex(where: { id($0) == sourceID }),
            let targetIndex = elements.firstIndex(where: { id($0) == targetID })
        else {
            return elements
        }

        var result = elements
        let source = result.remove(at: sourceIndex)
        result.insert(source, at: min(targetIndex, result.endIndex))
        return result
    }
}
