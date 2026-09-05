import Foundation

/// Keeps a terminal viewport attached to the bottom across layout changes
/// without overriding a user's deliberate scroll into history.
package struct TerminalBottomAnchorPolicy: Equatable, Sendable {
    package static let tolerance = 1.0

    /// Follow the live terminal tail until the user explicitly takes ownership
    /// of the viewport by dragging it. Layout transitions are not user intent:
    /// safe-area, keyboard, and Auto Layout passes may all expose temporary
    /// offsets while the final viewport is still settling.
    private var followsBottom = true

    package init() { }

    /// Returns the current bottom while the viewport follows live output.
    /// A nil result means the user owns the scroll position.
    package func targetOffset(maximumOffset: Double) -> Double? {
        followsBottom ? maximumOffset : nil
    }

    package mutating func userWillBeginScrolling() {
        followsBottom = false
    }

    /// Resume following only when the user deliberately returns to the tail.
    package mutating func userDidEndScrolling(
        currentOffset: Double,
        maximumOffset: Double
    ) {
        followsBottom = abs(currentOffset - maximumOffset) <= Self.tolerance
    }

    package mutating func requestScrollToBottom() {
        followsBottom = true
    }
}
