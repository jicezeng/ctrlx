import Foundation

/// Coalesces terminal bytes until the next MainActor turn and feeds SwiftTerm
/// with a bounded amount of work before yielding again.
@MainActor
final public class TerminalFeedCoalescer {
    private let id: String
    private let maximumFeedBytes: Int
    private let prioritizedFeedBytes: Int
    private let maximumTurnDuration: Duration
    private let metrics: TerminalTransportMetrics
    private let shouldPrioritizeInput: @MainActor () -> Bool
    private let feed: @MainActor (Data) -> Void

    private var chunks: [Data] = []
    private var headIndex = 0
    private var headOffset = 0
    private var pendingBytes = 0
    private var drainTask: Task<Void, Never>?
    private var drainToken: UUID?

    /// Creates a feed coalescer.
    ///
    /// A zero `maximumTurnDuration` preserves the original one-batch-per-turn
    /// behavior. Local terminals use a short time slice for bulk throughput.
    public init(
        id: String,
        maximumFeedBytes: Int = 32_768,
        prioritizedFeedBytes: Int = 4_096,
        maximumTurnDuration: Duration = .zero,
        metrics: TerminalTransportMetrics = .shared,
        shouldPrioritizeInput: @escaping @MainActor () -> Bool = { false },
        feed: @escaping @MainActor (Data) -> Void
    ) {
        precondition(maximumFeedBytes > 0)
        precondition(prioritizedFeedBytes > 0)
        precondition(maximumTurnDuration >= .zero)
        self.id = id
        self.maximumFeedBytes = maximumFeedBytes
        self.prioritizedFeedBytes = min(prioritizedFeedBytes, maximumFeedBytes)
        self.maximumTurnDuration = maximumTurnDuration
        self.metrics = metrics
        self.shouldPrioritizeInput = shouldPrioritizeInput
        self.feed = feed
    }

    public var queuedBytes: Int {
        pendingBytes
    }

    public func enqueue(_ data: Data) {
        guard !data.isEmpty else { return }
        chunks.append(data)
        pendingBytes += data.count
        recordQueue()
        scheduleDrainIfNeeded()
    }

    /// Drops bytes belonging to an obsolete terminal state before a snapshot reset.
    public func discardPending() {
        drainTask?.cancel()
        drainTask = nil
        drainToken = nil
        chunks.removeAll(keepingCapacity: true)
        headIndex = 0
        headOffset = 0
        pendingBytes = 0
        recordQueue()
    }

    /// Replaces all queued incremental data with an authoritative snapshot.
    /// The reset and feed are synchronous on MainActor so later increments cannot
    /// overtake the snapshot.
    public func replace(with data: Data, reset: @MainActor () -> Void) {
        discardPending()
        reset()
        feedNow(data)
    }

    /// Deterministic drain used by lifecycle boundaries and focused tests.
    public func flushPendingNow() {
        drainTask?.cancel()
        drainTask = nil
        drainToken = nil
        while let data = takeNextBatch(byteLimit: currentFeedByteLimit) {
            feedNow(data)
        }
    }

    private func scheduleDrainIfNeeded() {
        guard drainTask == nil else { return }
        let token = UUID()
        drainToken = token
        drainTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            var turnStartedAt = ContinuousClock.now

            while
                !Task.isCancelled,
                let data = self.takeNextBatch(byteLimit: self.currentFeedByteLimit) {
                self.feedNow(data)
                guard self.pendingBytes > 0 else { break }

                let inputIsWaiting = self.shouldPrioritizeInput()
                let turnExpired = self.maximumTurnDuration == .zero
                    || ContinuousClock.now - turnStartedAt >= self.maximumTurnDuration
                if inputIsWaiting || turnExpired {
                    await Task.yield()
                    turnStartedAt = .now
                }
            }

            guard self.drainToken == token else { return }
            self.drainTask = nil
            self.drainToken = nil
            if self.pendingBytes > 0 {
                self.scheduleDrainIfNeeded()
            }
        }
    }

    private var currentFeedByteLimit: Int {
        shouldPrioritizeInput() ? prioritizedFeedBytes : maximumFeedBytes
    }

    private func takeNextBatch(byteLimit: Int) -> Data? {
        guard pendingBytes > 0 else { return nil }
        let byteCount = min(byteLimit, pendingBytes)
        var result = Data()
        result.reserveCapacity(byteCount)

        while result.count < byteCount, headIndex < chunks.count {
            let chunk = chunks[headIndex]
            let available = chunk.count - headOffset
            let consumed = min(available, byteCount - result.count)
            let start = chunk.index(chunk.startIndex, offsetBy: headOffset)
            let end = chunk.index(start, offsetBy: consumed)
            result.append(contentsOf: chunk[start..<end])
            headOffset += consumed

            if headOffset == chunk.count {
                headIndex += 1
                headOffset = 0
            }
        }

        pendingBytes -= result.count
        compactConsumedChunks()
        recordQueue()
        return result
    }

    private func compactConsumedChunks() {
        if headIndex == chunks.count {
            chunks.removeAll(keepingCapacity: true)
            headIndex = 0
        } else if headIndex >= 32 {
            chunks.removeFirst(headIndex)
            headIndex = 0
        }
    }

    private func feedNow(_ data: Data) {
        guard !data.isEmpty else { return }
        let start = ContinuousClock.now
        feed(data)
        metrics.recordDuration(.terminalFeed, since: start)
    }

    private func recordQueue() {
        metrics.recordQueue(
            .terminalFeed,
            id: id,
            depth: chunks.count - headIndex,
            bytes: pendingBytes
        )
    }
}
