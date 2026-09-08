import CtrlxNetworking
import Foundation
import NIOCore
import Synchronization

struct RelayInboundFrame: Sendable {
    let data: Data
    let kind: RelayFrameKind
}

/// One connection's FIFO, including its validation barrier. Enqueue MUST run
/// synchronously on the WebSocket event loop, before creating any async work.
/// A single consumer awaits each complete decode/forward before taking the next
/// event. Actor isolation alone cannot provide that guarantee across awaits.
final class RelayInboundQueue: Sendable {
    enum Event: Sendable {
        case frame(RelayInboundFrame)
        case connected
    }

    enum Admission: Equatable {
        case accepted
        case overflow
        case closed
    }

    private struct State {
        var pending = CircularBuffer<Event>()
        var pendingBytes = 0
        var validated = false
        var finished = false

        mutating func finish() {
            finished = true
            pending.removeAll(keepingCapacity: false)
            pendingBytes = 0
        }
    }

    private let state = Mutex(State())
    private let maximumPendingFrames: Int
    private let maximumPendingBytes: Int
    private let maximumUnvalidatedBytes: Int
    // Only wakeups are coalesced; terminal frames are NEVER dropped/coalesced.
    private let wakeups: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(
        maximumPendingFrames: Int = 1024,
        maximumPendingBytes: Int = 8 * RelayPayloadLimits.maxWebSocketFrameBytes,
        maximumUnvalidatedBytes: Int = RelayPayloadLimits.maxWebSocketFrameBytes
    ) {
        self.maximumPendingFrames = maximumPendingFrames
        self.maximumPendingBytes = maximumPendingBytes
        self.maximumUnvalidatedBytes = maximumUnvalidatedBytes
        (wakeups, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func enqueue(_ frame: RelayInboundFrame) -> Admission {
        state.withLock { state in
            guard !state.finished else { return .closed }
            let limit = state.validated ? maximumPendingBytes : maximumUnvalidatedBytes
            guard state.pending.count < maximumPendingFrames,
                  frame.data.count <= limit - state.pendingBytes
            else {
                state.finish()
                continuation.finish()
                return .overflow
            }
            state.pending.append(.frame(frame))
            state.pendingBytes += frame.data.count
            continuation.yield()
            return .accepted
        }
    }

    /// Preserves the old ordering: early registration frames are processed before
    /// the connected notification, and subsequent frames follow the same FIFO.
    func activate() {
        state.withLock { state in
            guard !state.finished, !state.validated else { return }
            state.validated = true
            state.pending.append(.connected)
            continuation.yield()
        }
    }

    /// Exactly one caller per connection. The bound covers queued data; at most
    /// one additional WebSocket frame is being processed at any time.
    func consume(_ handle: @Sendable (Event) async -> Void) async {
        defer { finish() }
        for await _ in wakeups {
            while !Task.isCancelled, let event = takeNext() {
                await handle(event)
            }
            if isFinished || Task.isCancelled { return }
        }
    }

    private func takeNext() -> Event? {
        state.withLock { state in
            guard state.validated, !state.finished, !state.pending.isEmpty else { return nil }
            let event = state.pending.removeFirst()
            if case let .frame(frame) = event { state.pendingBytes -= frame.data.count }
            return event
        }
    }

    var isFinished: Bool { state.withLock { $0.finished } }

    func finish() {
        state.withLock { state in
            state.finish()
            continuation.finish()
        }
    }
}
