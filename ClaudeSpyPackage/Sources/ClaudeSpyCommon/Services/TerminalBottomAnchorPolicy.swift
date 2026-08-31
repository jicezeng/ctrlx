import Foundation

/// Keeps a terminal viewport attached to the bottom across layout changes
/// without overriding a user's deliberate scroll into history.
package struct TerminalBottomAnchorPolicy: Equatable, Sendable {
    package static let tolerance = 1.0

    private var previousMaximumOffset: Double?

    package init() { }

    /// Returns the new bottom offset when the viewport should remain anchored.
    /// A nil result means the user is away from the bottom and their position
    /// must be preserved.
    package mutating func targetOffset(
        currentOffset: Double,
        maximumOffset: Double,
        force: Bool = false
    ) -> Double? {
        let maximumOffset = max(0, maximumOffset)
        defer { previousMaximumOffset = maximumOffset }

        guard !force, let previousMaximumOffset else {
            return maximumOffset
        }

        let wasAtPreviousBottom = abs(currentOffset - previousMaximumOffset) <= Self.tolerance
        let isAtCurrentBottom = abs(currentOffset - maximumOffset) <= Self.tolerance
        return wasAtPreviousBottom || isAtCurrentBottom ? maximumOffset : nil
    }
}
