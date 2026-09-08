import Foundation
import Synchronization
import Testing
@testable import CtrlxExternalServerLib

@Suite("Relay inbound FIFO", .timeLimit(.minutes(1)))
struct RelayInboundQueueTests {
    private func frame(_ text: String, kind: RelayFrameKind = .binary) -> RelayInboundFrame {
        .init(data: Data(text.utf8), kind: kind)
    }

    @Test("Validation and live traffic share one FIFO and one notification barrier")
    func validationBarrier() async {
        let queue = RelayInboundQueue()
        let received = Recorder()
        #expect(queue.enqueue(frame("early text", kind: .text)) == .accepted)
        #expect(queue.enqueue(frame("early binary")) == .accepted)
        queue.activate()
        queue.activate() // Idempotent; no second notification.
        #expect(queue.enqueue(frame("live")) == .accepted)
        await queue.consume { event in
            received.append(event)
            if case let .frame(frame) = event, frame.data == Data("live".utf8) { queue.finish() }
        }
        #expect(received.values == ["early text", "early binary", "connected", "live"])
    }

    @Test("The next frame waits for the entire suspended forward to finish")
    func awaitsFullForward() async {
        let queue = RelayInboundQueue()
        let received = Recorder()
        let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        queue.activate()
        #expect(queue.enqueue(frame("first")) == .accepted)
        let consumer = Task {
            await queue.consume { event in
                guard case let .frame(frame) = event else { return }
                received.append("begin:" + String(decoding: frame.data, as: UTF8.self))
                if frame.data == Data("first".utf8) {
                    entered.continuation.yield()
                    for await _ in release.stream { break }
                }
                received.append("end:" + String(decoding: frame.data, as: UTF8.self))
                if frame.data == Data("last".utf8) { queue.finish() }
            }
        }
        for await _ in entered.stream { break }
        #expect(queue.enqueue(frame("last", kind: .text)) == .accepted)
        #expect(received.values == ["begin:first"])
        release.continuation.yield()
        await consumer.value
        #expect(received.values == ["begin:first", "end:first", "begin:last", "end:last"])
    }

    @Test("Rejection discards early frames and cannot be reopened")
    func rejectedValidation() async {
        let queue = RelayInboundQueue()
        let received = Recorder()
        #expect(queue.enqueue(frame("not authorized")) == .accepted)
        queue.finish()
        queue.activate()
        #expect(queue.enqueue(frame("later")) == .closed)
        await queue.consume { received.append($0) }
        #expect(received.values.isEmpty)
    }

    @Test("Both pre-validation and live byte limits fail closed", arguments: [false, true])
    func byteLimit(validated: Bool) async {
        let queue = RelayInboundQueue(maximumPendingBytes: 8, maximumUnvalidatedBytes: 4)
        let received = Recorder()
        if validated { queue.activate() }
        #expect(queue.enqueue(frame(String(repeating: "x", count: validated ? 8 : 4))) == .accepted)
        #expect(queue.enqueue(frame("!")) == .overflow)
        #expect(queue.isFinished)
        #expect(queue.enqueue(frame("after overflow")) == .closed)
        queue.activate()
        await queue.consume { received.append($0) }
        #expect(received.values.isEmpty, "Overflow must discard the partial stream, not continue after a hole")
    }

    @Test("Frame count is bounded even when payloads are empty")
    func frameCountLimit() async {
        let queue = RelayInboundQueue(maximumPendingFrames: 2)
        #expect(queue.enqueue(frame("")) == .accepted)
        #expect(queue.enqueue(frame("")) == .accepted)
        #expect(queue.enqueue(frame("")) == .overflow)
        #expect(queue.isFinished)
    }

    @Test("Close or replacement discards queued frames while a forward is suspended")
    func finishDuringForward() async {
        let queue = RelayInboundQueue()
        let received = Recorder()
        let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        queue.activate()
        #expect(queue.enqueue(frame("in flight")) == .accepted)
        let consumer = Task {
            await queue.consume { event in
                guard case .frame = event else { return }
                received.append(event)
                entered.continuation.yield()
                for await _ in release.stream { break }
            }
        }
        for await _ in entered.stream { break }
        #expect(queue.enqueue(frame("must not escape")) == .accepted)
        queue.finish()
        release.continuation.yield()
        await consumer.value
        #expect(received.values == ["in flight"])
        #expect(queue.enqueue(frame("stale")) == .closed)
    }

    @Test("Cancellation wakes an idle consumer and finishes its queue")
    func cancellation() async {
        let queue = RelayInboundQueue()
        let consumer = Task { await queue.consume { _ in } }
        consumer.cancel()
        await consumer.value
        #expect(queue.isFinished)
    }
}

private final class Recorder: Sendable {
    private let storage = Mutex<[String]>([])
    var values: [String] { storage.withLock { $0 } }
    func append(_ value: String) { storage.withLock { $0.append(value) } }
    func append(_ event: RelayInboundQueue.Event) {
        switch event {
        case let .frame(frame): append(String(decoding: frame.data, as: UTF8.self))
        case .connected: append("connected")
        }
    }
}
