#if os(macOS)
    import CtrlxCommon
    import CtrlxNetworking
    import Darwin
    import Dependencies
    import Foundation
    import Testing
    @testable import CtrlxServerFeature

    /// Captures every event a `PipePaneReader` emits so tests can assert on the
    /// exact stream the delegate sees. Lives on the main actor (matching the
    /// `PipePaneReaderDelegate` isolation).
    @MainActor
    final private class CapturingDelegate: PipePaneReaderDelegate {
        var data: [Data] = []
        var notifications: [TerminalStreamMessage.TerminalNotification] = []
        var titles: [String] = []
        var clipboards: [String] = []
        var progress: [TerminalProgressState] = []
        var overflowCount = 0
        var terminations: [PipePaneReaderTermination] = []

        func pipePaneReader(_ paneId: String, didReceiveData data: Data) {
            self.data.append(data)
        }

        func pipePaneReaderDidOverflow(_ paneId: String) {
            overflowCount += 1
        }

        func pipePaneReader(
            _ paneId: String,
            didReceiveNotification notification: TerminalStreamMessage.TerminalNotification
        ) {
            notifications.append(notification)
        }

        func pipePaneReader(_ paneId: String, didReceiveTitle title: String) {
            titles.append(title)
        }

        func pipePaneReader(_ paneId: String, didReceiveClipboard content: String) {
            clipboards.append(content)
        }

        func pipePaneReader(_ paneId: String, didReceiveProgress progress: TerminalProgressState) {
            self.progress.append(progress)
        }

        func pipePaneReader(
            _ reader: PipePaneReader,
            paneId: String,
            didTerminate reason: PipePaneReaderTermination
        ) {
            terminations.append(reason)
        }

        var concatenatedData: Data {
            data.reduce(Data()) { $0 + $1 }
        }
    }

    @Suite("TmuxControlClient Tests")
    struct TmuxControlClientTests {
        @Suite("Control Client Environment")
        struct ControlClientEnvironmentTests {
            @Test("Unavailable TERM uses xterm-256color")
            func unavailableTermUsesFallback() {
                for term in [String?.none, "", "dumb", "DUMB"] {
                    var inherited = ["PATH": "/usr/bin"]
                    inherited["TERM"] = term

                    let environment = TmuxControlClient.controlClientEnvironment(inheriting: inherited)

                    #expect(environment["TERM"] == "xterm-256color")
                    #expect(environment["PATH"] == "/usr/bin")
                }
            }

            @Test("Existing terminal type is preserved")
            func existingTermIsPreserved() {
                let inherited = ["TERM": "tmux-256color", "PATH": "/opt/homebrew/bin"]

                let environment = TmuxControlClient.controlClientEnvironment(inheriting: inherited)

                #expect(environment == inherited)
            }
        }

        @Suite("Process Lifecycle")
        struct ProcessLifecycleTests {
            @Test("Disconnect reaps only the control client and preserves its tmux pane")
            @MainActor
            func disconnectReapsControlClient() async throws {
                let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
                let suffix = UUID().uuidString.lowercased()
                let socketPath = "/tmp/ctrlx-control-\(suffix.prefix(8)).sock"
                let sessionName = "ctrlx-control-\(suffix)"
                defer { killTmuxServer(tmuxPath: tmuxPath, socketPath: socketPath) }

                try await withDependencies {
                    $0[ProcessRunner.self] = .liveValue
                } operation: {
                    let tmux = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                    let created = try await tmux.createSession(
                        baseName: sessionName,
                        width: 80,
                        height: 24
                    )
                    let client = TmuxControlClient(tmuxPath: tmuxPath, socketPath: socketPath)

                    try await client.connect(sessionTarget: created.sessionName)
                    let firstPID = try #require(await client.testProcessIdentifier)
                    #expect(processExists(firstPID))

                    await client.disconnect()
                    #expect(await client.testProcessIdentifier == nil)
                    #expect(!processExists(firstPID))

                    // Reusing the same actor catches a stale termination handler
                    // clearing the next connection after the old process exits.
                    try await client.connect(sessionTarget: created.sessionName)
                    let secondPID = try #require(await client.testProcessIdentifier)
                    #expect(secondPID != firstPID)
                    #expect(processExists(secondPID))
                    await client.disconnect()
                    #expect(!processExists(secondPID))

                    let panes = await tmux.refreshPanes()
                    #expect(panes.contains { $0.paneId == created.paneId })
                    _ = try await tmux.capturePaneText(created.paneId)
                }
            }

            private func processExists(_ pid: Int32) -> Bool {
                kill(pid, 0) == 0 || errno == EPERM
            }

            private func killTmuxServer(tmuxPath: String, socketPath: String) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tmuxPath)
                process.arguments = ["-S", socketPath, "kill-server"]
                process.environment = [:]
                process.standardError = Pipe()
                process.standardOutput = Pipe()
                try? process.run()
            }
        }

        // MARK: - Session Name Extraction Tests

        @Suite("Session Name Extraction")
        struct SessionNameExtractionTests {
            @Test("Full pane target extracts session name")
            @MainActor
            func fullPaneTarget() {
                let result = TmuxControlClientManager.extractSessionName(from: "mysession:0.1")
                #expect(result == "mysession")
            }

            @Test("Window target extracts session name")
            @MainActor
            func windowTarget() {
                let result = TmuxControlClientManager.extractSessionName(from: "mysession:0")
                #expect(result == "mysession")
            }

            @Test("Session only returns session name")
            @MainActor
            func sessionOnly() {
                let result = TmuxControlClientManager.extractSessionName(from: "mysession")
                #expect(result == "mysession")
            }

            @Test("Session with spaces before colon")
            @MainActor
            func sessionWithSpaces() {
                let result = TmuxControlClientManager.extractSessionName(from: "my session:0.1")
                #expect(result == "my session")
            }

            @Test("Session with numbers")
            @MainActor
            func sessionWithNumbers() {
                let result = TmuxControlClientManager.extractSessionName(from: "session123:2.0")
                #expect(result == "session123")
            }

            @Test("Pane ID format extracts correctly")
            @MainActor
            func paneIdFormat() {
                // Sometimes targets might be pane IDs like %0
                let result = TmuxControlClientManager.extractSessionName(from: "%0")
                #expect(result == "%0")
            }
        }

        // MARK: - Command Response Tests

        @Suite("Command Response")
        struct CommandResponseTests {
            @Test("Lines property splits output correctly")
            func linesPropertySplits() {
                let response = CommandResponse(
                    commandNumber: 1,
                    output: "line1\nline2\nline3",
                    isError: false
                )
                #expect(response.lines == ["line1", "line2", "line3"])
            }

            @Test("Lines property handles empty output")
            func linesPropertyEmpty() {
                let response = CommandResponse(
                    commandNumber: 1,
                    output: "",
                    isError: false
                )
                #expect(response.lines == [""])
            }

            @Test("Lines property preserves empty lines")
            func linesPropertyPreservesEmpty() {
                let response = CommandResponse(
                    commandNumber: 1,
                    output: "line1\n\nline3",
                    isError: false
                )
                #expect(response.lines == ["line1", "", "line3"])
            }
        }

        // MARK: - Error Types Tests

        @Suite("Error Types")
        struct ErrorTypesTests {
            @Test("Not connected error has correct description")
            func notConnectedError() {
                let error = TmuxControlError.notConnected
                #expect(error.errorDescription?.contains("Not connected") == true)
            }

            @Test("Already connected error has correct description")
            func alreadyConnectedError() {
                let error = TmuxControlError.alreadyConnected
                #expect(error.errorDescription?.contains("Already connected") == true)
            }

            @Test("Connection failed error includes message")
            func connectionFailedError() {
                let error = TmuxControlError.connectionFailed(message: "test error")
                #expect(error.errorDescription?.contains("test error") == true)
            }

            @Test("Process terminated error includes reason")
            func processTerminatedError() {
                let error = TmuxControlError.processTerminated(reason: "Exit code: 1")
                #expect(error.errorDescription?.contains("Exit code: 1") == true)
            }

            @Test("Process terminated error handles nil reason")
            func processTerminatedNilReason() {
                let error = TmuxControlError.processTerminated(reason: nil)
                #expect(error.errorDescription?.contains("unknown") == true)
            }

            @Test("Timeout error has correct description")
            func timeoutError() {
                let error = TmuxControlError.timeout
                #expect(error.errorDescription?.contains("timed out") == true)
            }
        }
    }

    // MARK: - Block Parsing Tests

    @Suite("Block Parsing")
    struct BlockParsingTests {
        /// Regression: `%error` used to only set a flag without resolving the queued
        /// continuation. The next `%end` would then pop the wrong entry and subsequent
        /// commands would drift, eventually timing out after ~5s — visible to users as
        /// a blank terminal after closing a tmux window.
        @Test("`%error` resolves queued command with isError=true")
        func errorBlockResolvesPendingCommand() async throws {
            let client = TmuxControlClient()
            await client.testMarkInitialAttachHandled()

            // Start each enqueue as an explicit Task and wait for it to land in
            // the queue before starting the next — `async let` doesn't guarantee
            // child-task scheduling order, so under load the wrong continuation
            // can end up at index 0.
            let first = Task { try await client.testEnqueueCommand(id: 1) }
            try await waitForPendingCount(client, equals: 1)
            let second = Task { try await client.testEnqueueCommand(id: 2) }
            try await waitForPendingCount(client, equals: 2)

            let chunk = Data("""
            %begin 1000 100 1
            can't find pane: %1
            %error 1000 100 1
            %begin 1001 101 1
            %end 1001 101 1

            """.utf8)
            await client.testProcessIncomingData(chunk)

            let firstResponse = try await first.value
            let secondResponse = try await second.value
            #expect(firstResponse.commandNumber == 100)
            #expect(firstResponse.isError == true)
            #expect(firstResponse.output == "can't find pane: %1")
            #expect(secondResponse.commandNumber == 101)
            #expect(secondResponse.isError == false)
            #expect(await client.testPendingCommandCount == 0)
        }

        @Test("`%end` resolves queued command with isError=false")
        func endBlockResolvesPendingCommand() async throws {
            let client = TmuxControlClient()
            await client.testMarkInitialAttachHandled()

            let first = Task { try await client.testEnqueueCommand(id: 1) }
            try await waitForPendingCount(client, equals: 1)

            let chunk = Data("""
            %begin 1000 100 1
            output-line
            %end 1000 100 1

            """.utf8)
            await client.testProcessIncomingData(chunk)

            let response = try await first.value
            #expect(response.commandNumber == 100)
            #expect(response.isError == false)
            #expect(response.output == "output-line")
            #expect(await client.testPendingCommandCount == 0)
        }

        /// Yields until the client's pending queue reaches `count`, with a
        /// generous timeout. Replaces `Task.sleep`-based synchronisation, which
        /// is wall-clock-racy under parallel test load on slow CI VMs.
        private func waitForPendingCount(
            _ client: TmuxControlClient,
            equals count: Int,
            timeout: Duration = .seconds(5)
        ) async throws {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while await client.testPendingCommandCount != count {
                if ContinuousClock.now >= deadline {
                    break
                }
                await Task.yield()
            }
            #expect(await client.testPendingCommandCount == count)
        }
    }

    // MARK: - PipePaneReader Tests

    @Suite("PipePaneReader Tests")
    struct PipePaneReaderTests {
        @Suite("Non-blocking reads")
        struct NonBlockingReadTests {
            @Test("Positive reads deliver data")
            func positiveRead() {
                #expect(PipePaneReadDisposition.classify(bytesRead: 42, errorCode: 0) == .data)
            }

            @Test("Transient errors keep the FIFO stream alive", arguments: [EAGAIN, EWOULDBLOCK, EINTR])
            func transientError(errorCode: Int32) {
                #expect(
                    PipePaneReadDisposition.classify(bytesRead: -1, errorCode: errorCode) == .retry
                )
            }

            @Test("EOF and permanent read errors terminate the FIFO stream")
            func terminalReadResults() {
                #expect(
                    PipePaneReadDisposition.classify(bytesRead: 0, errorCode: 0)
                        == .terminate(.endOfFile)
                )
                #expect(
                    PipePaneReadDisposition.classify(bytesRead: -1, errorCode: EIO)
                        == .terminate(.readError(EIO))
                )
            }
        }

        @Suite("Ingress backpressure")
        struct IngressBackpressureTests {
            @Test("Overflow drops stale chunks and marks the exact retained boundary")
            func overflowBoundary() {
                let buffer = PipeIngressBuffer(paneId: "%0", maximumChunks: 2)

                buffer.enqueue(Data("A".utf8))
                buffer.enqueue(Data("B".utf8))
                #expect(buffer.dequeue()?.data == Data("A".utf8))

                // B and C fill the queue while A is already being processed.
                // D must discard both and carry the reset marker itself.
                buffer.enqueue(Data("C".utf8))
                buffer.enqueue(Data("D".utf8))

                let retained = buffer.dequeue()
                #expect(retained?.data == Data("D".utf8))
                #expect(retained?.requiresResyncBefore == true)
                #expect(buffer.dequeue()?.data == nil)
            }

            @Test("Delegate backlog collapses to one snapshot boundary")
            @MainActor
            func delegateHighWater() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                let chunk = Data(repeating: 0x61, count: 65_536)
                await reader.testEnqueueDelegateData(Array(repeating: chunk, count: 9))
                await reader.testWaitForDelivery()

                #expect(delegate.data.isEmpty)
                #expect(delegate.overflowCount == 1)
            }

            @Test("Normal FIFO delivery does not request a snapshot")
            func normalDelivery() {
                let buffer = PipeIngressBuffer(paneId: "%0", maximumChunks: 2)
                buffer.enqueue(Data("A".utf8))
                buffer.enqueue(Data("B".utf8))

                let first = buffer.dequeue()
                let second = buffer.dequeue()
                #expect(first?.data == Data("A".utf8))
                #expect(first?.requiresResyncBefore == false)
                #expect(second?.data == Data("B".utf8))
                #expect(second?.requiresResyncBefore == false)
            }
        }

        @Suite("Tmux Escape Filtering")
        struct TmuxEscapeFilteringTests {
            @Test("Regular data passes through unchanged")
            func regularData() async {
                let reader = PipePaneReader(paneId: "%0")
                let input = Data("Hello, World!".utf8)
                let result = await reader.testFilterTmuxEscapeSequences(input)
                #expect(String(data: result, encoding: .utf8) == "Hello, World!")
            }

            @Test("ESC k title sequence is stripped")
            func escKTitleSequence() async {
                let reader = PipePaneReader(paneId: "%0")
                // ESC k title ESC \ followed by regular data
                var input = Data()
                input.append(0x1B) // ESC
                input.append(0x6B) // k
                input.append(contentsOf: "title".utf8)
                input.append(0x1B) // ESC
                input.append(0x5C) // backslash
                input.append(contentsOf: "visible".utf8)

                let result = await reader.testFilterTmuxEscapeSequences(input)
                #expect(String(data: result, encoding: .utf8) == "visible")
            }

            @Test("Other ESC sequences pass through")
            func otherEscSequences() async {
                let reader = PipePaneReader(paneId: "%0")
                // ESC [ 31m (red color) should pass through
                let input = Data([0x1B, 0x5B, 0x33, 0x31, 0x6D]) // ESC[31m
                let result = await reader.testFilterTmuxEscapeSequences(input)
                #expect(result == input)
            }

            @Test("Raw UTF-8 bytes pass through")
            func rawUtf8() async {
                let reader = PipePaneReader(paneId: "%0")
                let input = Data([0xE2, 0x94, 0x80]) // ─ (box drawing)
                let result = await reader.testFilterTmuxEscapeSequences(input)
                #expect(result == input)
                #expect(String(data: result, encoding: .utf8) == "─")
            }

            @Test("Mixed content with title sequence in the middle")
            func mixedContent() async {
                let reader = PipePaneReader(paneId: "%0")
                var input = Data("before".utf8)
                input.append(0x1B) // ESC
                input.append(0x6B) // k
                input.append(contentsOf: "title".utf8)
                input.append(0x1B) // ESC
                input.append(0x5C) // backslash
                input.append(contentsOf: "after".utf8)

                let result = await reader.testFilterTmuxEscapeSequences(input)
                #expect(String(data: result, encoding: .utf8) == "beforeafter")
            }

            @Test("Empty data returns empty")
            func emptyData() async {
                let reader = PipePaneReader(paneId: "%0")
                let result = await reader.testFilterTmuxEscapeSequences(Data())
                #expect(result.isEmpty)
            }
        }

        @Suite("FIFO Path")
        struct FifoPathTests {
            @Test("Pane ID is sanitized for filesystem")
            func paneIdSanitized() async {
                let reader = PipePaneReader(paneId: "%5")
                let path = await reader.testFifoPath
                let expectedDir = FileManager.default.temporaryDirectory.path
                #expect(path == "\(expectedDir)/ctrlx-pipe-5.fifo")
            }
        }

        @Suite("Buffering")
        @MainActor
        struct BufferingTests {
            @Test("setBuffering(true) → bytes arrive → flushBuffer() delivers them in order")
            func bufferedBytesFlushedInOrder() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("first ".utf8))
                await reader.testProcessIncomingData(Data("second ".utf8))
                await reader.testProcessIncomingData(Data("third".utf8))

                #expect(delegate.data.isEmpty, "Buffered bytes must not reach delegate before flush")

                await reader.flushBuffer()

                #expect(delegate.data.count == 3)
                let combined = String(data: delegate.concatenatedData, encoding: .utf8)
                #expect(combined == "first second third")
            }

            @Test("setBuffering(false) stops Data delivery but keeps OSC events flowing")
            func scanOnlyStillEmitsOSC() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                // Default mode after creation is scan-only — explicit toggle just
                // mirrors what the manager does on last-unsubscribe.
                await reader.setBuffering(false)

                // OSC 9 notification + plain text in one chunk.
                var input = Data()
                input.append(contentsOf: "before".utf8)
                input.append(0x1B) // ESC
                input.append(0x5D) // ]
                input.append(contentsOf: "9;hello".utf8)
                input.append(0x07) // BEL
                input.append(contentsOf: "after".utf8)

                await reader.testProcessIncomingData(input)
                await reader.testWaitForDelivery()

                #expect(delegate.data.isEmpty, "Scan-only mode must not deliver data bytes")
                #expect(delegate.notifications.count == 1, "OSC 9 notification must still flow")
            }

            @Test("A split OSC sequence is resumed even when the next chunk is plain")
            func splitOSCResumesSlowPath() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)
                await reader.setBuffering(false)

                await reader.testProcessIncomingData(Data([0x1B, 0x5D]) + Data("9;split".utf8))
                await reader.testProcessIncomingData(Data(" message".utf8) + Data([0x07]))
                await reader.testWaitForDelivery()

                #expect(delegate.data.isEmpty)
                #expect(delegate.notifications.map(\.body) == ["split message"])
            }

            @Test("flushBuffer keeps order even when bytes arrive during the drain")
            func flushBufferOrderingUnderConcurrentInput() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("A".utf8))
                await reader.testProcessIncomingData(Data("B".utf8))

                // Actor serialization: whichever method enters the actor first
                // runs to completion. If flushBuffer wins, it dispatches a Task
                // for [A, B] then flips mode to .live; the late C call then sees
                // .live and dispatches its own Task. If the late call wins, it
                // appends C to the buffer; flushBuffer then dispatches a Task
                // for [A, B, C]. Either way, MainActor processes the dispatched
                // Tasks in submission order, yielding "ABC".
                async let flushTask: () = reader.flushBuffer()
                async let lateTask: () = reader.testProcessIncomingData(Data("C".utf8))
                _ = await (flushTask, lateTask)
                await reader.testWaitForDelivery()

                let combined = String(data: delegate.concatenatedData, encoding: .utf8) ?? ""
                #expect(combined == "ABC", "Expected A,B,C in order, got: \(combined)")
            }

            @Test("flushBuffer returns only after buffered bytes reach the delegate")
            func flushWaitsForDelegateDelivery() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("ready".utf8))
                await reader.flushBuffer()

                #expect(delegate.concatenatedData == Data("ready".utf8))
            }

            @Test("flushBuffer completes when the weak delegate is gone")
            func flushWithoutDelegateDoesNotHang() async {
                let reader = PipePaneReader(paneId: "%0")
                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("discarded".utf8))

                await reader.flushBuffer()
            }

            @Test("flushBuffer transitions to live: subsequent bytes flow directly")
            func flushTransitionsToLive() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("buffered".utf8))
                await reader.flushBuffer()
                await reader.testWaitForDelivery()

                #expect(delegate.data.count == 1)

                // Live mode: bytes go straight to the delegate, in the same order
                // relative to the previously buffered chunk.
                await reader.testProcessIncomingData(Data(" live".utf8))
                await reader.testWaitForDelivery()
                #expect(delegate.data.count == 2)
                let combined = String(data: delegate.concatenatedData, encoding: .utf8)
                #expect(combined == "buffered live")
            }

            @Test("Toggling buffering on→off→on starts a fresh buffer (off drops queue)")
            func togglingBufferingDropsQueueOnDisable() async {
                let reader = PipePaneReader(paneId: "%0")
                let delegate = CapturingDelegate()
                await reader.setDelegate(delegate)

                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("dropped".utf8))

                // Manager calls setBuffering(false) when the last subscriber leaves;
                // any bytes that hadn't been flushed are intentionally discarded.
                await reader.setBuffering(false)

                // Re-enable buffering and confirm the queue starts fresh.
                await reader.setBuffering(true)
                await reader.testProcessIncomingData(Data("kept".utf8))
                await reader.flushBuffer()
                await reader.testWaitForDelivery()
                #expect(delegate.data.count == 1)
                #expect(String(data: delegate.data[0], encoding: .utf8) == "kept")
            }
        }
    }
#endif
