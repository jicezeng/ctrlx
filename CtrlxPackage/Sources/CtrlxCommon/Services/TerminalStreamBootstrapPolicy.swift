import Foundation

/// Coordinates the two independent events required before a remote terminal
/// can be presented: a valid initial snapshot and the host's start-command
/// acknowledgement.
package struct TerminalStreamBootstrapPolicy: Equatable {
    package private(set) var acceptsInitialState = false
    package private(set) var hasInitialState = false
    package private(set) var hasCompleteSnapshot = false
    package private(set) var hasStartAcknowledgement = false

    package var isReady: Bool {
        hasInitialState && hasCompleteSnapshot && hasStartAcknowledgement
    }

    package init() { }

    /// Starts a new attempt while rejecting snapshots left in flight by an old
    /// stream. Call `willSendStartRequest()` only after any replacement stop
    /// command has completed.
    package mutating func beginAttempt() {
        acceptsInitialState = false
        hasInitialState = false
        hasCompleteSnapshot = false
        hasStartAcknowledgement = false
    }

    package mutating func willSendStartRequest() {
        acceptsInitialState = true
        hasInitialState = false
        hasCompleteSnapshot = false
        hasStartAcknowledgement = false
    }

    /// Returns true when this is the first valid snapshot for the active start
    /// request. Broadcast refreshes and duplicate snapshots are ignored.
    package mutating func receiveInitialState(snapshotIsComplete: Bool = true) -> Bool {
        guard acceptsInitialState, !hasInitialState else { return false }
        acceptsInitialState = false
        hasInitialState = true
        hasCompleteSnapshot = snapshotIsComplete
        return true
    }

    /// A replacement snapshot received during bootstrap supersedes every byte
    /// buffered before it and becomes the new readiness boundary.
    package mutating func expectSnapshotCompletion() {
        guard hasInitialState else { return }
        hasCompleteSnapshot = false
    }

    package mutating func receiveSnapshotCompletion() {
        guard hasInitialState else { return }
        hasCompleteSnapshot = true
    }

    package mutating func receiveStartAcknowledgement() {
        hasStartAcknowledgement = true
    }
}

/// Holds terminal bootstrap work until the start command is acknowledged and
/// the viewer has received the complete advertised snapshot. Adjacent data
/// chunks are coalesced so SwiftTerm parses and schedules display work only
/// once in the common case. Dimension changes remain ordered relative to
/// terminal bytes.
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

/// Collects a chunked terminal snapshot without exposing its intermediate
/// parser state. The host serializes complete snapshot transactions per pane,
/// so the advertised byte count is the only boundary needed to separate the
/// snapshot from later live bytes.
package struct TerminalStreamSnapshotAccumulator: Equatable, Sendable {
    package struct Completion: Equatable, Sendable {
        package let content: Data
        package let remainder: Data
    }

    package private(set) var expectedByteCount: Int?
    private var content = Data()

    package var isCollecting: Bool {
        expectedByteCount != nil
    }

    package init() { }

    /// Starts a new snapshot and drops any incomplete older one. A zero-byte
    /// snapshot completes immediately.
    package mutating func begin(expectedByteCount: Int) -> Completion? {
        precondition(expectedByteCount >= 0)
        self.expectedByteCount = expectedByteCount
        content.removeAll(keepingCapacity: true)
        return finishIfComplete(remainder: Data())
    }

    /// Consumes bytes up to the advertised boundary. Any bytes after that
    /// boundary are returned for normal incremental processing.
    package mutating func append(_ data: Data) -> Completion? {
        guard let expectedByteCount else { return nil }

        let remainingByteCount = expectedByteCount - content.count
        let consumedByteCount = min(remainingByteCount, data.count)
        content.append(data.prefix(consumedByteCount))
        let remainder = Data(data.dropFirst(consumedByteCount))
        return finishIfComplete(remainder: remainder)
    }

    package mutating func cancel() {
        expectedByteCount = nil
        content.removeAll(keepingCapacity: true)
    }

    private mutating func finishIfComplete(remainder: Data) -> Completion? {
        guard let expectedByteCount, content.count == expectedByteCount else {
            return nil
        }

        let completion = Completion(content: content, remainder: remainder)
        cancel()
        return completion
    }
}
