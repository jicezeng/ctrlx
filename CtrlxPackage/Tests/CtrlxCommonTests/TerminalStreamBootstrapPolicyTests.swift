import Foundation
import Testing
@testable import CtrlxCommon

@Suite("Terminal stream bootstrap policy")
struct TerminalStreamBootstrapPolicyTests {
    @Test("Initial state alone does not reveal the terminal")
    func initialNeedsAcknowledgement() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.beginAttempt()
        policy.willSendStartRequest()

        let accepted = policy.receiveInitialState()
        #expect(accepted)
        #expect(!policy.isReady)

        policy.receiveStartAcknowledgement()
        #expect(policy.isReady)
    }

    @Test("Acknowledgement may arrive before initial state")
    func acknowledgementNeedsInitialState() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.beginAttempt()
        policy.willSendStartRequest()

        policy.receiveStartAcknowledgement()
        #expect(!policy.isReady)

        let accepted = policy.receiveInitialState()
        #expect(accepted)
        #expect(policy.isReady)
    }

    @Test("Counted snapshots must finish after acknowledgement")
    func countedSnapshotNeedsCompletion() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.beginAttempt()
        policy.willSendStartRequest()

        let accepted = policy.receiveInitialState(snapshotIsComplete: false)
        #expect(accepted)
        policy.receiveStartAcknowledgement()
        #expect(!policy.isReady)

        policy.receiveSnapshotCompletion()
        #expect(policy.isReady)
    }

    @Test("A replacement snapshot restores the completion barrier")
    func replacementSnapshotNeedsCompletion() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.willSendStartRequest()
        _ = policy.receiveInitialState()
        policy.receiveStartAcknowledgement()
        #expect(policy.isReady)

        policy.expectSnapshotCompletion()
        #expect(!policy.isReady)
        policy.receiveSnapshotCompletion()
        #expect(policy.isReady)
    }

    @Test("Replacement stop window rejects stale snapshots")
    func staleInitialStateIsRejected() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.beginAttempt()

        let staleAccepted = policy.receiveInitialState()
        #expect(!staleAccepted)

        policy.willSendStartRequest()
        let accepted = policy.receiveInitialState()
        let duplicateAccepted = policy.receiveInitialState()
        #expect(accepted)
        #expect(!duplicateAccepted)
    }

    @Test("New attempt clears prior readiness")
    func newAttemptClearsReadyState() {
        var policy = TerminalStreamBootstrapPolicy()
        policy.willSendStartRequest()
        let accepted = policy.receiveInitialState()
        #expect(accepted)
        policy.receiveStartAcknowledgement()
        #expect(policy.isReady)

        policy.beginAttempt()
        #expect(!policy.isReady)
        #expect(!policy.acceptsInitialState)
    }
}

@Suite("Terminal stream bootstrap buffer")
struct TerminalStreamBootstrapBufferTests {
    @Test("Initial state and data chunks become one feed")
    func coalescesAdjacentData() {
        var buffer = TerminalStreamBootstrapBuffer()

        buffer.appendDimensions(cols: 80, rows: 24)
        buffer.appendData(Data("initial".utf8))
        buffer.appendData(Data("-one".utf8))
        buffer.appendData(Data("-two".utf8))

        #expect(buffer.takeEvents() == [
            .dimensions(cols: 80, rows: 24),
            .data(Data("initial-one-two".utf8)),
        ])
        #expect(buffer.takeEvents().isEmpty)
    }

    @Test("Dimension changes preserve terminal byte order")
    func preservesDimensionBoundaries() {
        var buffer = TerminalStreamBootstrapBuffer()

        buffer.appendDimensions(cols: 80, rows: 24)
        buffer.appendData(Data("before".utf8))
        buffer.appendDimensions(cols: 120, rows: 40)
        buffer.appendData(Data("after".utf8))

        #expect(buffer.takeEvents() == [
            .dimensions(cols: 80, rows: 24),
            .data(Data("before".utf8)),
            .dimensions(cols: 120, rows: 40),
            .data(Data("after".utf8)),
        ])
    }

    @Test("Reset drops bytes from a stale stream attempt")
    func resetDropsStaleData() {
        var buffer = TerminalStreamBootstrapBuffer()
        buffer.appendDimensions(cols: 80, rows: 24)
        buffer.appendData(Data("stale".utf8))

        buffer.reset()
        buffer.appendDimensions(cols: 100, rows: 30)
        buffer.appendData(Data("current".utf8))

        #expect(buffer.takeEvents() == [
            .dimensions(cols: 100, rows: 30),
            .data(Data("current".utf8)),
        ])
    }
}

@Suite("Terminal stream snapshot accumulator")
struct TerminalStreamSnapshotAccumulatorTests {
    @Test("Snapshot remains pending until every advertised byte arrives")
    func waitsForCompleteSnapshot() {
        var accumulator = TerminalStreamSnapshotAccumulator()

        #expect(accumulator.begin(expectedByteCount: 6) == nil)
        #expect(accumulator.append(Data("abc".utf8)) == nil)
        #expect(accumulator.isCollecting)

        let completion = accumulator.append(Data("def".utf8))
        #expect(completion?.content == Data("abcdef".utf8))
        #expect(completion?.remainder.isEmpty == true)
        #expect(!accumulator.isCollecting)
    }

    @Test("Bytes beyond the snapshot boundary remain live data")
    func preservesTrailingLiveData() {
        var accumulator = TerminalStreamSnapshotAccumulator()

        _ = accumulator.begin(expectedByteCount: 4)
        let completion = accumulator.append(Data("snapshot-tail".utf8))

        #expect(completion?.content == Data("snap".utf8))
        #expect(completion?.remainder == Data("shot-tail".utf8))
    }

    @Test("A newer snapshot supersedes an incomplete snapshot")
    func newerSnapshotSupersedesOlderOne() {
        var accumulator = TerminalStreamSnapshotAccumulator()

        _ = accumulator.begin(expectedByteCount: 5)
        _ = accumulator.append(Data("old".utf8))
        _ = accumulator.begin(expectedByteCount: 3)
        let completion = accumulator.append(Data("new".utf8))

        #expect(completion?.content == Data("new".utf8))
    }

    @Test("An empty snapshot completes at its metadata boundary")
    func emptySnapshotCompletesImmediately() {
        var accumulator = TerminalStreamSnapshotAccumulator()

        let completion = accumulator.begin(expectedByteCount: 0)

        #expect(completion?.content.isEmpty == true)
        #expect(completion?.remainder.isEmpty == true)
        #expect(!accumulator.isCollecting)
    }
}
