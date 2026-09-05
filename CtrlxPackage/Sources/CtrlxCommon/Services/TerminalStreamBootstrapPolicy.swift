import Foundation

/// Coordinates the two independent events required before a remote terminal
/// can be presented: a valid initial snapshot and the host's start-command
/// acknowledgement.
package struct TerminalStreamBootstrapPolicy: Equatable {
    package private(set) var acceptsInitialState = false
    package private(set) var hasInitialState = false
    package private(set) var hasStartAcknowledgement = false

    package var isReady: Bool {
        hasInitialState && hasStartAcknowledgement
    }

    package init() { }

    /// Starts a new attempt while rejecting snapshots left in flight by an old
    /// stream. Call `willSendStartRequest()` only after any replacement stop
    /// command has completed.
    package mutating func beginAttempt() {
        acceptsInitialState = false
        hasInitialState = false
        hasStartAcknowledgement = false
    }

    package mutating func willSendStartRequest() {
        acceptsInitialState = true
        hasInitialState = false
        hasStartAcknowledgement = false
    }

    /// Returns true when this is the first valid snapshot for the active start
    /// request. Broadcast refreshes and duplicate snapshots are ignored.
    package mutating func receiveInitialState() -> Bool {
        guard acceptsInitialState, !hasInitialState else { return false }
        acceptsInitialState = false
        hasInitialState = true
        return true
    }

    package mutating func receiveStartAcknowledgement() {
        hasStartAcknowledgement = true
    }
}

/// Holds terminal bootstrap work until the host confirms that every byte
/// captured during startup has reached the viewer. Adjacent data chunks are
/// coalesced so SwiftTerm parses and schedules display work only once in the
/// common case. Dimension changes remain ordered relative to terminal bytes.
package struct TerminalStreamBootstrapBuffer: Equatable {
    package enum Event: Equatable {
        case dimensions(cols: Int, rows: Int)
        case data(Data)
    }

    private var events: [Event] = []
    private var pendingData = Data()

    package init() { }

    package mutating func reset() {
        events = []
        pendingData = Data()
    }

    package mutating func appendData(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingData.append(data)
    }

    package mutating func appendDimensions(cols: Int, rows: Int) {
        flushPendingData()

        let dimensions = Event.dimensions(cols: cols, rows: rows)
        if case .dimensions = events.last {
            events[events.index(before: events.endIndex)] = dimensions
        } else {
            events.append(dimensions)
        }
    }

    package mutating func takeEvents() -> [Event] {
        flushPendingData()
        let result = events
        reset()
        return result
    }

    private mutating func flushPendingData() {
        guard !pendingData.isEmpty else { return }
        events.append(.data(pendingData))
        pendingData = Data()
    }
}
