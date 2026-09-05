#if os(macOS)
    import CtrlxCommon
    import CtrlxNetworking
    import Foundation
    import Logging
    import os.lock

    enum PipePaneReaderTermination: Equatable, Sendable, CustomStringConvertible {
        case endOfFile
        case readError(Int32)

        var description: String {
            switch self {
            case .endOfFile:
                "EOF"
            case let .readError(errorCode):
                "read error \(errorCode): \(String(cString: strerror(errorCode)))"
            }
        }
    }

    enum PipePaneReadDisposition: Equatable, Sendable {
        case data
        case retry
        case terminate(PipePaneReaderTermination)

        static func classify(bytesRead: Int, errorCode: Int32) -> Self {
            if bytesRead > 0 { return .data }
            if bytesRead == 0 { return .terminate(.endOfFile) }
            if errorCode == EAGAIN || errorCode == EWOULDBLOCK || errorCode == EINTR {
                return .retry
            }
            return .terminate(.readError(errorCode))
        }
    }

    /// Receives events parsed by `PipePaneReader`.
    ///
    /// All methods are called on the main actor. The reader coalesces pending
    /// events into one MainActor delivery loop. Normal live delivery remains
    /// fire-and-forget; `flushBuffer()` inserts a barrier when a subscriber
    /// needs proof that bootstrap bytes reached the delegate. Individual data
    /// chunks remain separate delegate calls and retain their FIFO order.
    @MainActor
    protocol PipePaneReaderDelegate: AnyObject, Sendable {
        func pipePaneReader(_ paneId: String, didReceiveData data: Data)
        func pipePaneReaderDidOverflow(_ paneId: String)
        func pipePaneReader(
            _ paneId: String,
            didReceiveNotification notification: TerminalStreamMessage.TerminalNotification
        )
        func pipePaneReader(_ paneId: String, didReceiveTitle title: String)
        func pipePaneReader(_ paneId: String, didReceiveClipboard content: String)
        func pipePaneReader(_ paneId: String, didReceiveProgress progress: TerminalProgressState)
        func pipePaneReader(
            _ reader: PipePaneReader,
            paneId: String,
            didTerminate reason: PipePaneReaderTermination
        )
    }

    /// Manages FIFO-based raw byte delivery from tmux pipe-pane for a single pane.
    ///
    /// A single `PipePaneReader` lives for the full lifetime of its tmux pane.
    /// It starts in scan-only mode (data discarded, OSC notifications still
    /// extracted) and switches into buffering / live modes via
    /// `setBuffering(_:)` and `flushBuffer()` when subscribers attach.
    ///
    /// Instead of parsing `%output` events from control mode (which requires octal unescaping,
    /// UTF-8 reconstruction, and line-boundary handling), this reads raw PTY bytes directly
    /// via `pipe-pane -O` piped through a FIFO. The only filtering needed is stripping
    /// tmux's `ESC k ... ESC \` title sequences.
    ///
    /// FIFO connection sequence:
    /// 1. Create FIFO with `mkfifo()`
    /// 2. Send `pipe-pane` command through control mode (returns immediately)
    /// 3. tmux starts `cat > fifo` subprocess (blocks on open until reader connects)
    /// 4. Open FIFO for reading (unblocks writer, data flows)
    actor PipePaneReader {
        /// Three data-delivery modes the reader can be in.
        ///
        /// - `scanOnly`: parser is in scan-only mode (no `filteredData` built),
        ///   incoming bytes are discarded. OSC notification/title/clipboard/progress
        ///   events still flow to the delegate. This is the default after start
        ///   and the resting state when no subscribers are attached.
        /// - `buffering`: parser builds `filteredData`, but bytes are queued
        ///   for a later `flushBuffer()` instead of being forwarded. Used during
        ///   an initial `capture-pane` snapshot so live bytes that arrive
        ///   between "buffering on" and "snapshot taken" aren't dropped.
        /// - `live`: parser builds `filteredData` and bytes flow directly to the
        ///   delegate. The state after `flushBuffer()` returns.
        private enum Mode: Equatable { case scanOnly, buffering, live }

        /// `paneId` never changes after init; expose nonisolated so the delegate
        /// (which receives the id with every callback) doesn't need to cross
        /// actor boundaries to read it.
        nonisolated let paneId: String
        private let logger: Logging.Logger

        // FIFO state
        private let fifoPath: String
        private var fileHandle: FileHandle?
        private var isRunning = false
        private var isStopping = false
        private var terminationReported = false
        private var streamGeneration: UUID?

        // Delivery
        private weak var delegate: (any PipePaneReaderDelegate)?
        private var mode: Mode = .scanOnly
        private var buffer: [Data] = []
        private var bufferedBytes = 0
        private var bufferOverflowed = false
        private var pendingDelegateEvents: [DelegateEvent] = []
        private var pendingDelegateHeadIndex = 0
        private var pendingDelegateBytes = 0
        private var delegateDeliveryScheduled = false
        private var delegateBackpressured = false

        // AsyncStream for FIFO-ordered data processing.
        // readabilityHandler yields into this stream; a single consumer task
        // processes chunks in order, preventing the reordering that occurs
        // with unstructured Task {} per callback.
        private var dataContinuation: AsyncStream<Void>.Continuation?
        private var consumerTask: Task<Void, Never>?
        private let ingressBuffer: PipeIngressBuffer

        /// Eight maximum-size FIFO reads keep at most 512 KiB before the parser.
        /// An overflow resets parser state and asks subscribers for a snapshot;
        /// continuing with a byte gap would corrupt ANSI state.
        private static let ingressBufferChunks = 8
        private static let maximumCaptureBufferBytes = 2 * 1_024 * 1_024
        private static let maximumPendingDelegateBytes = 512 * 1_024
        private static let maximumDelegateEventsPerTurn = 32
        private static let maximumDelegateBytesPerTurn = 256 * 1_024

        /// Incomplete tmux escape sequence buffer (ESC k ... ESC \ split across reads)
        private var tmuxEscapeBuffer = Data()

        /// Parser for OSC 9/777 notification sequences. `scanOnly` is flipped
        /// by `setBuffering(_:)` so the same instance can be reused across modes.
        private var notificationParser = TerminalNotificationParser(scanOnly: true)

        init(paneId: String) {
            self.paneId = paneId
            self.logger = Logging.Logger(label: "com.jicezeng.ctrlx.pipepane.\(paneId)")
            self.ingressBuffer = PipeIngressBuffer(
                paneId: paneId,
                maximumChunks: Self.ingressBufferChunks
            )

            // Sanitize pane ID for filesystem: "%5" -> "5"
            let sanitized = paneId.replacingOccurrences(of: "%", with: "")
            precondition(
                !sanitized.isEmpty && sanitized.allSatisfy(\.isNumber),
                "Pane ID must contain only digits after stripping '%', got: \(paneId)"
            )
            let tmpDir = FileManager.default.temporaryDirectory.path
            self.fifoPath = "\(tmpDir)/ctrlx-pipe-\(sanitized).fifo"
        }

        // MARK: - Public API

        /// Sets the delegate that receives parsed events. Stored weakly; the
        /// delegate must outlive the reader.
        func setDelegate(_ delegate: (any PipePaneReaderDelegate)?) {
            self.delegate = delegate
        }

        /// Starts pipe-pane for this pane, creating the FIFO and opening it for reading.
        ///
        /// The reader begins in scan-only mode — bytes are parsed for OSC events
        /// but discarded otherwise. Use `setBuffering(true)` + `flushBuffer()`
        /// when a subscriber attaches and wants live bytes.
        ///
        /// - Parameter controlClientManager: Used to send the pipe-pane command
        /// - Parameter sessionName: The tmux session name for the control client
        func startPipePane(
            controlClientManager: TmuxControlClientManager,
            sessionName: String
        ) async throws {
            guard !isRunning else {
                logger.warning("pipe-pane already running for \(paneId)")
                return
            }

            isStopping = false
            terminationReported = false
            mode = .scanOnly
            notificationParser.scanOnly = true
            buffer = []
            bufferedBytes = 0
            bufferOverflowed = false

            // Clean up any stale FIFO from a previous crash
            cleanupFifo()

            // Step 1: Create FIFO (retry once if stale file persists after cleanup)
            var result = mkfifo(fifoPath, 0o600)
            if result != 0, errno == EEXIST {
                logger.warning("FIFO still exists after cleanup, force-removing: \(fifoPath)")
                try? FileManager.default.removeItem(atPath: fifoPath)
                result = mkfifo(fifoPath, 0o600)
            }
            guard result == 0 else {
                let errorMessage = String(cString: strerror(errno))
                throw PipePaneError.fifoCreationFailed(path: fifoPath, message: errorMessage)
            }

            logger.debug("Created FIFO at \(fifoPath)")

            // Step 2: Stop any existing pipe-pane for this pane, then start new one
            _ = try? await controlClientManager.sendCommand(
                "pipe-pane -t '\(paneId)'",
                sessionName: sessionName
            )
            _ = try await controlClientManager.sendCommand(
                "pipe-pane -O -t '\(paneId)' 'exec cat > \"\(fifoPath)\"'",
                sessionName: sessionName
            )

            logger.debug("pipe-pane command sent for \(paneId)")

            // Step 3: Open FIFO for reading (this unblocks the cat writer)
            // Must be done on a background thread since open() blocks until writer connects
            let path = fifoPath
            let handle = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FileHandle, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let fd = open(path, O_RDONLY | O_NONBLOCK)
                    if fd < 0 {
                        let errorMessage = String(cString: strerror(errno))
                        continuation.resume(throwing: PipePaneError.fifoOpenFailed(
                            path: path, message: errorMessage
                        ))
                    } else {
                        continuation.resume(returning: FileHandle(fileDescriptor: fd, closeOnDealloc: true))
                    }
                }
            }

            fileHandle = handle
            isRunning = true
            let generation = UUID()
            streamGeneration = generation

            // Step 4: Set up AsyncStream for FIFO-ordered data delivery.
            // readabilityHandler fires on a dispatch queue — yielding into the stream
            // is synchronous and non-blocking. A single consumer task drains the stream
            // in order, guaranteeing no data reordering.
            let (stream, continuation) = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            dataContinuation = continuation

            // Note: readabilityHandler captures `continuation` strongly, so the handler
            // keeps yielding if PipePaneReader is deallocated without stopPipePane().
            // Callers MUST call stopPipePane() to clean up — see PaneStreamManager.
            let fd = handle.fileDescriptor
            handle.readabilityHandler = { [weak self] _ in
                // Read directly from the file descriptor to avoid NSFileHandle's
                // -availableData which throws an uncatchable NSException if the
                // descriptor was closed between the dispatch source firing and
                // the handler executing.
                var buf = [UInt8](repeating: 0, count: 65_536)
                let bytesRead = read(fd, &buf, buf.count)
                let errorCode = bytesRead < 0 ? errno : 0
                switch PipePaneReadDisposition.classify(
                    bytesRead: bytesRead,
                    errorCode: errorCode
                ) {
                case .data:
                    let data = Data(buf[..<bytesRead])
                    self?.ingressBuffer.enqueue(data)
                    continuation.yield()

                case .retry:
                    // A non-blocking descriptor can transiently report no data
                    // after the dispatch source fires. Keep the stream alive;
                    // the source will invoke us again when bytes are readable.
                    return

                case let .terminate(reason):
                    continuation.finish()
                    Task { [weak self] in
                        await self?.handleTermination(reason, generation: generation)
                    }
                }
            }

            // Single consumer task — processes data in strict FIFO order
            consumerTask = Task { [weak self] in
                for await _ in stream {
                    guard let self else { break }
                    await self.drainIngressBuffer()
                }
            }

            logger.info("pipe-pane started for \(paneId)")
        }

        /// Switches data-delivery mode.
        ///
        /// - `true`: Switch to buffering mode. The parser starts building
        ///   `filteredData` and incoming bytes are queued instead of forwarded
        ///   to the delegate. Drop any prior buffered bytes first — buffering
        ///   is meant to start clean before a `capture-pane` snapshot.
        /// - `false`: Switch back to scan-only mode. The parser stops building
        ///   `filteredData`, the queue is discarded, and only OSC events keep
        ///   flowing. Call when the last subscriber leaves.
        ///
        /// Use `flushBuffer()` to drain the queue and transition into live mode
        /// (bytes flow directly to the delegate).
        func setBuffering(_ enabled: Bool) {
            buffer = []
            bufferedBytes = 0
            bufferOverflowed = false
            delegateBackpressured = false
            if enabled {
                // A snapshot supersedes queued live bytes. Keep control events
                // and barriers, but do not spend MainActor time replaying output
                // that every subscriber will immediately replace.
                _ = discardPendingDelegateData()
                recordDelegateQueue()
                notificationParser.scanOnly = false
                mode = .buffering
            } else {
                notificationParser.scanOnly = true
                mode = .scanOnly
            }
        }

        /// Drains any queued bytes through the delegate in the order they were
        /// received, then transitions to live mode (subsequent bytes flow
        /// directly to the delegate). The buffer is empty after this call.
        ///
        /// The method returns only after all buffered chunks have reached the
        /// delegate. Live chunks that arrive after the inserted barrier remain
        /// fire-and-forget and continue through the same FIFO queue.
        func flushBuffer() async {
            notificationParser.scanOnly = false
            let toFlush = bufferOverflowed ? [] : buffer
            let didOverflow = bufferOverflowed
            buffer = []
            bufferedBytes = 0
            bufferOverflowed = false
            mode = .live

            await withCheckedContinuation { continuation in
                var events = toFlush.map(DelegateEvent.data)
                if didOverflow {
                    events.append(.overflow)
                }
                events.append(.barrier(continuation))
                enqueueDelegateEvents(events)
            }
            logger.debug("Flushed \(toFlush.count) buffered chunks for \(paneId)")
        }

        /// Stops pipe-pane and cleans up all resources.
        ///
        /// - Parameter controlClientManager: Used to send the stop pipe-pane command
        /// - Parameter sessionName: The tmux session name
        func stopPipePane(
            controlClientManager: TmuxControlClientManager,
            sessionName: String
        ) async {
            guard isRunning else { return }

            logger.debug("Stopping pipe-pane for \(paneId)")
            isStopping = true
            streamGeneration = nil

            // Stop the readability handler and stream first
            fileHandle?.readabilityHandler = nil
            dataContinuation?.finish()
            dataContinuation = nil
            let task = consumerTask
            task?.cancel()
            consumerTask = nil
            _ = await task?.value
            try? fileHandle?.close()
            fileHandle = nil

            // Stop pipe-pane in tmux (this terminates the cat process)
            _ = try? await controlClientManager.sendCommand(
                "pipe-pane -t '\(paneId)'",
                sessionName: sessionName
            )

            // Clean up FIFO
            cleanupFifo()

            isRunning = false
            isStopping = false
            terminationReported = false
            mode = .scanOnly
            buffer = []
            bufferedBytes = 0
            bufferOverflowed = false
            discardPendingDelegateEvents()
            ingressBuffer.removeAll()
            tmuxEscapeBuffer = Data()
            notificationParser.reset()
            notificationParser.scanOnly = true
            logger.info("pipe-pane stopped for \(paneId)")
        }

        /// A stopped dispatch handler may still enqueue a late callback. The
        /// generation check in `handleTermination` rejects that callback after
        /// this reader has been restarted for the same pane.
        var isHealthy: Bool {
            isRunning && !isStopping && !terminationReported
        }

        // MARK: - Data Processing

        private func processIncomingData(_ data: Data) {
            guard !data.isEmpty else { return }

            // Terminal output is overwhelmingly plain UTF-8. Avoid six full
            // Data scans and the OSC parser when this chunk cannot contain a
            // control sequence. Buffered fragments disable this path because
            // the current chunk may complete a sequence begun by the previous
            // read without containing another introducer itself.
            if canUsePlainDataPath(data) {
                processPlainData(data)
                return
            }

            // Filter tmux-specific escape sequences (ESC k ... ESC \)
            let tmuxFiltered = filterTmuxEscapeSequences(data)
            guard !tmuxFiltered.isEmpty else { return }

            // Strip DA query sequences so mirroring SwiftTerm instances never
            // see them and never generate response bytes in their send() delegate.
            let daFiltered = TerminalResponseFilter.stripDAQueries(tmuxFiltered)
            guard !daFiltered.isEmpty else { return }

            // Strip DSR query sequences (CPR, DECXCPR, status) for the same reason.
            let dsrFiltered = TerminalResponseFilter.stripDSRQueries(daFiltered)
            guard !dsrFiltered.isEmpty else { return }

            // Strip DECRQM (Request Mode) queries — e.g. mode 2026 synchronized output.
            let decrqmFiltered = TerminalResponseFilter.stripDECRQMQueries(dsrFiltered)
            guard !decrqmFiltered.isEmpty else { return }

            // Strip Kitty keyboard protocol negotiation sequences so mirroring
            // SwiftTerm instances never enter an unsupported keyboard mode.
            let kittyFiltered = TerminalResponseFilter.stripKittyKeyboardProtocol(decrqmFiltered)
            guard !kittyFiltered.isEmpty else { return }

            // Strip OSC color queries (background/foreground/cursor/palette probes)
            // so mirroring SwiftTerm instances never emit a color report that would
            // leak back into the pane as typed input (e.g. `11;rgb:…`) — issue #669.
            let oscFiltered = TerminalResponseFilter.stripOSCColorQueries(kittyFiltered)
            guard !oscFiltered.isEmpty else { return }

            // Parse and strip OSC 9/777 notification sequences
            let parseResult = notificationParser.parse(oscFiltered)

            // Determine what (if any) data goes to the live delegate; for
            // buffering mode we append synchronously so the buffer's order
            // is determined by actor serialization, not by MainActor timing.
            let filtered = parseResult.filteredData
            let liveData: Data?
            switch mode {
            case .scanOnly:
                liveData = nil
            case .buffering:
                appendToCaptureBuffer(filtered)
                liveData = nil
            case .live:
                liveData = filtered.isEmpty ? nil : filtered
            }

            let notifications = parseResult.notifications
            let title = parseResult.titleChange.map(TerminalTitleStabilizer.stabilize)
            let clipboard = parseResult.clipboardContent
            let progress = parseResult.progressUpdate

            guard
                !notifications.isEmpty
                || title != nil
                || clipboard != nil
                || progress != nil
                || liveData != nil
            else { return }

            var events = notifications.map(DelegateEvent.notification)
            if let title { events.append(.title(title)) }
            if let clipboard { events.append(.clipboard(clipboard)) }
            if let progress { events.append(.progress(progress)) }
            if let liveData { events.append(.data(liveData)) }
            enqueueDelegateEvents(events)
        }

        private func canUsePlainDataPath(_ data: Data) -> Bool {
            tmuxEscapeBuffer.isEmpty
                && !notificationParser.hasBufferedSequence
                && !data.contains(0x1B) // ESC
                && !data.contains(0x9B) // C1 CSI
                && !data.contains(0x9D) // C1 OSC
        }

        private func processPlainData(_ data: Data) {
            switch mode {
            case .scanOnly:
                return
            case .buffering:
                appendToCaptureBuffer(data)
            case .live:
                enqueueDelegateEvents([.data(data)])
            }
        }

        /// Adds events to the FIFO delivery queue. One MainActor task drains
        /// every event currently available instead of spawning a task for
        /// every pipe read.
        private func enqueueDelegateEvents(_ events: [DelegateEvent]) {
            guard !events.isEmpty else { return }
            for event in events {
                switch event {
                case let .data(data):
                    guard !delegateBackpressured else { continue }
                    guard pendingDelegateBytes + data.count <= Self.maximumPendingDelegateBytes else {
                        let alreadyHasOverflow = discardPendingDelegateData()
                        delegateBackpressured = true
                        if !alreadyHasOverflow {
                            pendingDelegateEvents.append(.overflow)
                        }
                        continue
                    }
                    pendingDelegateEvents.append(event)
                    pendingDelegateBytes += data.count

                case .overflow:
                    guard !delegateBackpressured else { continue }
                    delegateBackpressured = true
                    pendingDelegateEvents.append(event)

                case .notification, .title, .clipboard, .progress, .barrier:
                    pendingDelegateEvents.append(event)
                }
            }
            recordDelegateQueue()
            guard !delegateDeliveryScheduled else { return }

            delegateDeliveryScheduled = true
            Task { @MainActor [weak self] in
                while let delivery = await self?.takePendingDelegateDelivery() {
                    delivery.deliver()
                    await Task.yield()
                }
            }
        }

        private func takePendingDelegateDelivery() -> DelegateDelivery? {
            guard !pendingDelegateEvents.isEmpty else {
                delegateDeliveryScheduled = false
                return nil
            }

            let availableCount = pendingDelegateEvents.count - pendingDelegateHeadIndex
            var eventCount = 0
            var byteCount = 0
            while eventCount < availableCount,
                  eventCount < Self.maximumDelegateEventsPerTurn {
                let nextBytes = pendingDelegateEvents[pendingDelegateHeadIndex + eventCount].byteCount
                if eventCount > 0, byteCount + nextBytes > Self.maximumDelegateBytesPerTurn {
                    break
                }
                byteCount += nextBytes
                eventCount += 1
            }

            let endIndex = pendingDelegateHeadIndex + eventCount
            let events = Array(pendingDelegateEvents[pendingDelegateHeadIndex..<endIndex])
            pendingDelegateHeadIndex = endIndex
            pendingDelegateBytes -= byteCount
            compactPendingDelegateEvents()
            recordDelegateQueue()
            return DelegateDelivery(
                paneId: paneId,
                delegate: WeakDelegate(delegate),
                events: events
            )
        }

        private enum DelegateEvent: Sendable {
            case notification(TerminalStreamMessage.TerminalNotification)
            case title(String)
            case clipboard(String)
            case progress(TerminalProgressState)
            case data(Data)
            case overflow
            case barrier(CheckedContinuation<Void, Never>)

            var byteCount: Int {
                if case let .data(data) = self { return data.count }
                return 0
            }
        }

        private struct DelegateDelivery: Sendable {
            let paneId: String
            let delegate: WeakDelegate
            let events: [DelegateEvent]

            @MainActor
            func deliver() {
                for event in events {
                    switch event {
                    case let .notification(notification):
                        delegate.value?.pipePaneReader(paneId, didReceiveNotification: notification)
                    case let .title(title):
                        delegate.value?.pipePaneReader(paneId, didReceiveTitle: title)
                    case let .clipboard(clipboard):
                        delegate.value?.pipePaneReader(paneId, didReceiveClipboard: clipboard)
                    case let .progress(progress):
                        delegate.value?.pipePaneReader(paneId, didReceiveProgress: progress)
                    case let .data(data):
                        delegate.value?.pipePaneReader(paneId, didReceiveData: data)
                    case .overflow:
                        delegate.value?.pipePaneReaderDidOverflow(paneId)
                    case let .barrier(continuation):
                        continuation.resume()
                    }
                }
            }
        }

        private func appendToCaptureBuffer(_ data: Data) {
            guard !data.isEmpty, !bufferOverflowed else { return }
            guard bufferedBytes + data.count <= Self.maximumCaptureBufferBytes else {
                buffer.removeAll(keepingCapacity: true)
                bufferedBytes = 0
                bufferOverflowed = true
                return
            }
            buffer.append(data)
            bufferedBytes += data.count
        }

        private func handleIngressOverflow() {
            tmuxEscapeBuffer = Data()
            notificationParser.reset()
            notificationParser.scanOnly = mode == .scanOnly
            buffer.removeAll(keepingCapacity: true)
            bufferedBytes = 0
            switch mode {
            case .scanOnly:
                bufferOverflowed = false
            case .buffering:
                // Keep the marker until flushBuffer. This forces a second
                // snapshot if the gap raced the current capture boundary.
                bufferOverflowed = true
            case .live:
                bufferOverflowed = false
                enqueueDelegateEvents([.overflow])
            }
        }

        private func drainIngressBuffer() async {
            var processedChunks = 0
            var processedBytes = 0
            while !Task.isCancelled,
                  processedChunks < Self.maximumDelegateEventsPerTurn,
                  processedBytes < Self.maximumDelegateBytesPerTurn,
                  let item = ingressBuffer.dequeue() {
                if item.requiresResyncBefore {
                    handleIngressOverflow()
                }
                processIncomingData(item.data)
                processedChunks += 1
                processedBytes += item.data.count
            }

            if ingressBuffer.hasPendingData {
                dataContinuation?.yield()
                await Task.yield()
            }
        }

        private func recordDelegateQueue() {
            TerminalTransportMetrics.shared.recordQueue(
                .pipeIngress,
                id: "\(paneId):delegate",
                depth: pendingDelegateEvents.count - pendingDelegateHeadIndex,
                bytes: pendingDelegateBytes
            )
        }

        private func compactPendingDelegateEvents() {
            if pendingDelegateHeadIndex == pendingDelegateEvents.count {
                pendingDelegateEvents.removeAll(keepingCapacity: true)
                pendingDelegateHeadIndex = 0
            } else if pendingDelegateHeadIndex >= 64,
                      pendingDelegateHeadIndex * 2 >= pendingDelegateEvents.count {
                pendingDelegateEvents.removeFirst(pendingDelegateHeadIndex)
                pendingDelegateHeadIndex = 0
            }
        }

        private func discardPendingDelegateEvents() {
            let pending = pendingDelegateEvents[pendingDelegateHeadIndex...]
            let barriers = pending.compactMap { event -> CheckedContinuation<Void, Never>? in
                if case let .barrier(continuation) = event { return continuation }
                return nil
            }
            pendingDelegateEvents.removeAll(keepingCapacity: false)
            pendingDelegateHeadIndex = 0
            pendingDelegateBytes = 0
            delegateBackpressured = false
            recordDelegateQueue()
            for continuation in barriers {
                continuation.resume()
            }
        }

        private func discardPendingDelegateData() -> Bool {
            let retained = pendingDelegateEvents[pendingDelegateHeadIndex...].filter { event in
                if case .data = event { return false }
                return true
            }
            pendingDelegateEvents = retained
            pendingDelegateHeadIndex = 0
            pendingDelegateBytes = 0
            return retained.contains { event in
                if case .overflow = event { return true }
                return false
            }
        }

        /// Tiny weak holder so we can capture the delegate reference into a
        /// `Sendable` closure without retaining it.
        private struct WeakDelegate: @unchecked Sendable {
            weak var value: (any PipePaneReaderDelegate)?
            init(_ value: (any PipePaneReaderDelegate)?) {
                self.value = value
            }
        }

        /// Filters out tmux/screen-specific escape sequences that standard terminals don't handle.
        /// - `ESC k ... ESC \` : tmux title sequence (sets pane title)
        /// Without filtering, terminals output the sequence content as literal text.
        /// Buffers incomplete sequences across reads to handle split data.
        private func filterTmuxEscapeSequences(_ data: Data) -> Data {
            var result = Data()

            // Prepend any buffered incomplete sequence from previous read
            var dataToProcess = data
            if !tmuxEscapeBuffer.isEmpty {
                dataToProcess = tmuxEscapeBuffer + data
                tmuxEscapeBuffer = Data()
            }

            var i = dataToProcess.startIndex

            while i < dataToProcess.endIndex {
                if dataToProcess[i] == 0x1B { // ESC
                    if i + 1 >= dataToProcess.endIndex {
                        // Incomplete: just ESC at end, buffer it
                        tmuxEscapeBuffer = Data(dataToProcess[i...])
                        break
                    }

                    if dataToProcess[i + 1] == 0x6B { // 'k'
                        // ESC k - start of tmux title sequence
                        // Skip until we find ESC \ (0x1B 0x5C) or end of data
                        var j = dataToProcess.index(i, offsetBy: 2)
                        var foundEnd = false

                        while j < dataToProcess.endIndex {
                            if dataToProcess[j] == 0x1B {
                                if j + 1 >= dataToProcess.endIndex {
                                    // ESC at end while inside sequence - buffer from start
                                    tmuxEscapeBuffer = Data(dataToProcess[i...])
                                    return result
                                }
                                if dataToProcess[j + 1] == 0x5C { // '\'
                                    // Found ESC \ - skip entire sequence
                                    j = dataToProcess.index(j, offsetBy: 2)
                                    foundEnd = true
                                    break
                                }
                            }
                            j = dataToProcess.index(after: j)
                        }

                        if foundEnd {
                            i = j
                        } else {
                            // Reached end without finding ESC \ - buffer incomplete sequence
                            tmuxEscapeBuffer = Data(dataToProcess[i...])
                            break
                        }
                    } else {
                        // ESC followed by something other than 'k' - pass through
                        result.append(dataToProcess[i])
                        i = dataToProcess.index(after: i)
                    }
                } else {
                    result.append(dataToProcess[i])
                    i = dataToProcess.index(after: i)
                }
            }

            return result
        }

        // MARK: - Test Helpers

        /// Exposes filterTmuxEscapeSequences for testing.
        func testFilterTmuxEscapeSequences(_ data: Data) -> Data {
            filterTmuxEscapeSequences(data)
        }

        /// Exposes processIncomingData for testing. The data path itself is
        /// synchronous, but delegate delivery is fire-and-forget on MainActor;
        /// tests must call `testWaitForDelivery()` before asserting on the
        /// delegate so any dispatched Tasks have run.
        func testProcessIncomingData(_ data: Data) {
            processIncomingData(data)
        }

        /// Enqueues one atomic delegate batch so tests can exercise the
        /// downstream high-water boundary without scheduler timing.
        func testEnqueueDelegateData(_ chunks: [Data]) {
            enqueueDelegateEvents(chunks.map(DelegateEvent.data))
        }

        /// Drains any MainActor delivery work dispatched by prior
        /// `testProcessIncomingData` / `flushBuffer` calls. Tests assert on
        /// delegate state only after this returns.
        func testWaitForDelivery() async {
            while delegateDeliveryScheduled {
                await Task.yield()
            }
        }

        /// Exposes fifoPath for testing.
        var testFifoPath: String {
            fifoPath
        }

        // MARK: - Lifecycle

        private func handleTermination(
            _ reason: PipePaneReaderTermination,
            generation: UUID
        ) async {
            guard
                isRunning,
                !isStopping,
                !terminationReported,
                streamGeneration == generation
            else { return }

            terminationReported = true
            logger.warning("pipe-pane FIFO terminated for \(paneId): \(reason)")
            fileHandle?.readabilityHandler = nil
            dataContinuation?.finish()
            await delegate?.pipePaneReader(self, paneId: paneId, didTerminate: reason)
        }

        private func cleanupFifo() {
            unlink(fifoPath)
        }

        /// Cleans up stale FIFOs from previous crashes.
        /// Call once at startup.
        static func cleanupStaleFifos() {
            let fm = FileManager.default
            let tmpDir = fm.temporaryDirectory.path
            guard let contents = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
            for file in contents where file.hasPrefix("ctrlx-pipe-") && file.hasSuffix(".fifo") {
                let path = "\(tmpDir)/\(file)"
                try? fm.removeItem(atPath: path)
                Logging.Logger(label: "com.jicezeng.ctrlx.pipepane").debug("Cleaned up stale FIFO: \(path)")
            }
        }
    }

    /// Small thread-safe handoff between FileHandle's dispatch callback and the
    /// reader actor. On overflow it discards the stale queue and marks the first
    /// retained chunk as a resync boundary. A global overflow flag is racy here:
    /// the producer can overflow again while the actor is processing an older
    /// dequeued chunk, causing the reset to be applied at the wrong byte.
    final class PipeIngressBuffer: Sendable {
        struct Item: Sendable {
            let data: Data
            let requiresResyncBefore: Bool
        }

        private struct State: Sendable {
            var items: [Item] = []
            var bytes = 0
        }

        private let paneId: String
        private let maximumChunks: Int
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(paneId: String, maximumChunks: Int) {
            precondition(maximumChunks > 0)
            self.paneId = paneId
            self.maximumChunks = maximumChunks
        }

        func enqueue(_ data: Data) {
            guard !data.isEmpty else { return }
            let sample = state.withLock { state in
                let overflowed = state.items.count >= maximumChunks
                if overflowed {
                    state.items.removeAll(keepingCapacity: true)
                    state.bytes = 0
                }
                state.items.append(Item(data: data, requiresResyncBefore: overflowed))
                state.bytes += data.count
                return (state.items.count, state.bytes)
            }
            record(depth: sample.0, bytes: sample.1)
        }

        func dequeue() -> Item? {
            let sample: (item: Item?, depth: Int, bytes: Int) = state.withLock { state in
                guard !state.items.isEmpty else { return (nil, 0, 0) }
                let item = state.items.removeFirst()
                state.bytes -= item.data.count
                return (item, state.items.count, state.bytes)
            }
            record(depth: sample.depth, bytes: sample.bytes)
            return sample.item
        }

        var hasPendingData: Bool {
            state.withLock { !$0.items.isEmpty }
        }

        func removeAll() {
            state.withLock { state in
                state.items.removeAll(keepingCapacity: false)
                state.bytes = 0
            }
            record(depth: 0, bytes: 0)
        }

        private func record(depth: Int, bytes: Int) {
            TerminalTransportMetrics.shared.recordQueue(
                .pipeIngress,
                id: "\(paneId):fifo",
                depth: depth,
                bytes: bytes
            )
        }
    }

    // MARK: - Errors

    enum PipePaneError: Error, LocalizedError {
        case fifoCreationFailed(path: String, message: String)
        case fifoOpenFailed(path: String, message: String)

        var errorDescription: String? {
            switch self {
            case let .fifoCreationFailed(path, message):
                return "Failed to create FIFO at \(path): \(message)"
            case let .fifoOpenFailed(path, message):
                return "Failed to open FIFO at \(path): \(message)"
            }
        }
    }
#endif
