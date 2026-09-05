/// Monotonic identity for work owned by one transport connection.
///
/// Capture `current` before suspending. Any reconnect or cleanup invalidates
/// that value, so an old task cannot act on the replacement socket.
package struct ConnectionGeneration: Equatable, Sendable {
    package private(set) var current: UInt64 = 0

    package init() { }

    package mutating func invalidate() {
        current &+= 1
    }

    package func isCurrent(_ generation: UInt64) -> Bool {
        current == generation
    }
}

/// Requires more than one silent keepalive round before declaring a socket dead.
package struct ConnectionLivenessPolicy: Equatable, Sendable {
    package let missedRoundLimit: Int
    package private(set) var consecutiveMissedRounds = 0

    package init(missedRoundLimit: Int = 2) {
        precondition(missedRoundLimit > 0)
        self.missedRoundLimit = missedRoundLimit
    }

    package mutating func receivedInboundFrame() {
        consecutiveMissedRounds = 0
    }

    /// Returns true only when the configured consecutive-miss limit is reached.
    package mutating func missedRound() -> Bool {
        consecutiveMissedRounds += 1
        return consecutiveMissedRounds >= missedRoundLimit
    }
}
