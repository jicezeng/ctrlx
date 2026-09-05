import Foundation

/// Tracks whether a terminal view has already requested its host stream.
///
/// The first request must not send `StopTerminalStream`: another viewer may be
/// the only current subscriber. Later requests replace this view's previous
/// subscription with stop/start so reconnects refresh the complete screen and
/// keep the host's subscriber count balanced.
package struct TerminalStreamRecoveryPolicy: Equatable {
    package static let unexpectedEndWindow: TimeInterval = 30
    package static let maximumUnexpectedEndRetries = 2

    package enum StartMode: Equatable {
        case initial
        case replaceExisting
    }

    package enum SuccessfulStartResolution: Equatable {
        case ready
        case retryReplacement
        case failMissingInitialState
    }

    package private(set) var hasRequestedStream = false
    package private(set) var unexpectedEndRetryDates: [Date] = []

    package init() { }

    package mutating func nextStartMode() -> StartMode {
        defer { hasRequestedStream = true }
        return hasRequestedStream ? .replaceExisting : .initial
    }

    /// Allows isolated automatic replacements while bounding a tight failure
    /// loop. A stable stream explicitly clears this rolling-window budget.
    package mutating func shouldRetryUnexpectedEnd(
        isConnected: Bool,
        now: Date = Date()
    ) -> Bool {
        guard isConnected else { return false }
        unexpectedEndRetryDates.removeAll { date in
            let age = now.timeIntervalSince(date)
            return age < 0 || age >= Self.unexpectedEndWindow
        }
        guard unexpectedEndRetryDates.count < Self.maximumUnexpectedEndRetries else {
            return false
        }
        unexpectedEndRetryDates.append(now)
        return true
    }

    package mutating func markStreamingStable() {
        unexpectedEndRetryDates.removeAll(keepingCapacity: true)
    }

    package static func resolveSuccessfulStart(
        hasInitialState: Bool,
        canRetry: Bool
    ) -> SuccessfulStartResolution {
        if hasInitialState {
            return .ready
        } else if canRetry {
            return .retryReplacement
        } else {
            return .failMissingInitialState
        }
    }
}
