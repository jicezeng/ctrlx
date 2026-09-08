#if os(macOS)
    import CtrlxCommon
    import Dependencies
    import Foundation
    import SwiftTerm
    import Testing
    @testable import CtrlxServerFeature

    /// Exercise the real control protocol, not two independently mocked streams.
    /// Every test owns a private tmux server and a raw echo pane (no user shell rc).
    @Suite("Pane stream consistency", .serialized)
    @MainActor
    struct PaneStreamConsistencyTests {
        @Test("Stable pane targets share the discovery session's control connection")
        func stableTargetUsesOneConnection() async throws {
            try await withPane { fixture in
                await fixture.streams.startMonitoring(panes: [fixture.pane])
                let subscription = try await fixture.streams.subscribe(
                    paneId: fixture.pane.paneId,
                    target: fixture.pane.paneId,
                    onData: { _ in }
                )
                #expect(try await fixture.controlClientCount() == 1)
                await fixture.streams.unsubscribe(subscription.subscriptionId)
            }
        }

        @Test("On-demand subscription resolves a pane ID to its owning session")
        func onDemandUsesCanonicalSession() async throws {
            try await withPane { fixture in
                let subscription = try await fixture.streams.subscribe(
                    paneId: fixture.pane.paneId,
                    target: fixture.pane.paneId,
                    onData: { _ in }
                )
                _ = try await fixture.clients.getClient(for: fixture.pane.sessionName)
                #expect(try await fixture.controlClientCount() == 1)
                await fixture.streams.updateMonitoring(panes: [fixture.pane])
                await fixture.streams.unsubscribe(subscription.subscriptionId)
            }
        }

        @Test("Reopening a pane never delivers a non-idempotent update twice")
        func reopeningDoesNotDuplicateOutput() async throws {
            try await withPane { fixture in
                await fixture.streams.startMonitoring(panes: [fixture.pane])
                let first = try await fixture.streams.subscribe(
                    paneId: fixture.pane.paneId,
                    target: fixture.pane.paneId,
                    onData: { _ in }
                )
                await fixture.streams.unsubscribe(first.subscriptionId)

                let rendered = CapturedTerminal(cols: fixture.pane.width, rows: fixture.pane.height)
                let second = try await fixture.streams.subscribe(
                    paneId: fixture.pane.paneId,
                    target: fixture.pane.target,
                    onData: { rendered.feed($0) }
                )
                rendered.feed(second.initialContent)
                let update = "\r\nLIVE_ONCE\r\n"
                try await fixture.write(update)
                // Let both control readers drain, including the obsolete reader
                // that the old pane-ID/session-name mismatch left enabled.
                try await Task.sleep(for: .milliseconds(100))

                #expect(rendered.text.components(separatedBy: "LIVE_ONCE").count - 1 == 1)
                #expect(rendered.text == (try await fixture.visibleText()))
                #expect(try await fixture.controlClientCount() == 1)
                await fixture.streams.unsubscribe(second.subscriptionId)
            }
        }

        @Test("Concurrent first requests create exactly one session control client")
        func concurrentConnectionCreationIsCoalesced() async throws {
            try await withPane { fixture in
                let manager = fixture.clients
                let sessionName = fixture.pane.sessionName
                let clients = try await withThrowingTaskGroup(of: TmuxControlClient.self) { group in
                    for _ in 0..<8 {
                        group.addTask {
                            try await manager.getClient(for: sessionName)
                        }
                    }
                    var clients: [TmuxControlClient] = []
                    for try await client in group { clients.append(client) }
                    return clients
                }
                #expect(Set(clients.map(ObjectIdentifier.init)).count == 1)
                // Process.run() precedes tmux's attach handshake. Wait for a
                // real response before counting server-side registrations.
                if let client = clients.first {
                    _ = try await client.sendCommand("display-message -p CONNECTED")
                }
                #expect(try await fixture.controlClientCount() == 1)
                // Reap every returned child even when testing the broken code.
                var reaped = Set<ObjectIdentifier>()
                for client in clients where reaped.insert(ObjectIdentifier(client)).inserted {
                    await client.disconnect()
                }
            }
        }

        @Test("A failed capture list cannot consume the next command's response")
        func failedCommandListKeepsResponseAlignment() async throws {
            try await withPane { fixture in
                let client = try await fixture.clients.getClient(for: fixture.pane.sessionName)
                let responses = try await client.sendCommandList([
                    "display-message -p BEFORE_ERROR",
                    "capture-pane -p -t %2147483647",
                    "display-message -p MUST_BE_SKIPPED",
                ])
                #expect(responses.count == 2)
                #expect(responses.first?.output == "BEFORE_ERROR")
                #expect(responses.last?.isError == true)
                let next = try await client.sendCommand("display-message -p AFTER_ERROR")
                #expect(next.output == "AFTER_ERROR")
                #expect(!next.isError)
            }
        }

        @Test("Long output remains identical for simultaneous and newly joined subscribers")
        func longOutputHasNoGapsAcrossSnapshotBoundaries() async throws {
            try await withPane { fixture in
                await fixture.streams.startMonitoring(panes: [fixture.pane])
                let writer = Task { @MainActor in
                    for revision in 1...80 {
                        try Task.checkCancellation()
                        try await fixture.tmux.sendRawBytes(
                            fixture.pane.paneId,
                            data: Data("\r\nROW_\(revision) 中文内容".utf8)
                        )
                    }
                }
                do {
                    var terminals: [CapturedTerminal] = []
                    for _ in 0..<10 {
                        let rendered = CapturedTerminal(cols: fixture.pane.width, rows: fixture.pane.height)
                        let subscription = try await fixture.streams.subscribe(
                            paneId: fixture.pane.paneId, target: fixture.pane.paneId,
                            onData: { rendered.feed($0) }
                        )
                        rendered.feed(subscription.initialContent)
                        terminals.append(rendered)
                    }
                    try await writer.value
                    try await fixture.waitForText("ROW_80")
                    try await Task.sleep(for: .milliseconds(100))
                    let expected = try await fixture.visibleText()
                    for rendered in terminals { #expect(rendered.text == expected) }
                    #expect(try await fixture.controlClientCount() == 1)
                } catch {
                    writer.cancel()
                    _ = try? await writer.value
                    throw error
                }
            }
        }

        @Test("A changing screen and its cursor are captured from the same instant", arguments: [0, 1_000])
        func captureDoesNotMixCursorAndScreenRevisions(scrollback: Int) async throws {
            try await withPane { fixture in
                try await fixture.tmux.sendRawBytes(
                    fixture.pane.paneId, data: Data("\u{1b}[2J\u{1b}[2;1HFRAME".utf8)
                )
                try await fixture.waitForText("FRAME")
                let writer = Task { @MainActor in
                    for revision in 0..<80 {
                        try Task.checkCancellation()
                        let row = 2 + revision % 8
                        try await fixture.tmux.sendRawBytes(
                            fixture.pane.paneId,
                            data: Data("\u{1b}[2J\u{1b}[\(row);1HFRAME".utf8)
                        )
                    }
                }
                do {
                    for _ in 0..<80 {
                        let snapshot = try await fixture.tmux.capturePaneViaControlMode(
                            paneId: fixture.pane.paneId, width: fixture.pane.width, height: fixture.pane.height,
                            controlClientManager: fixture.clients, sessionName: fixture.pane.sessionName,
                            scrollbackLineLimit: scrollback
                        )
                        let rendered = CapturedTerminal(cols: fixture.pane.width, rows: fixture.pane.height)
                        rendered.feed(snapshot)
                        #expect(rendered.cursorLine == "FRAME")
                    }
                    try await writer.value
                } catch {
                    writer.cancel()
                    _ = try? await writer.value
                    throw error
                }
            }
        }

        private func withPane(_ operation: @MainActor (Fixture) async throws -> Void) async throws {
            let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
            let socketPath = "/tmp/ctrlx-consistency-\(UUID().uuidString.prefix(8)).sock"
            // tmux pane IDs restart at %0 on each server. A private socket
            // alone does NOT isolate the scan-only FIFO from a running CtrlX.
            let fifoDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ctrlx-consistency-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: fifoDirectory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: fifoDirectory) }
            try await withDependencies {
                $0[ProcessRunner.self] = .liveValue
            } operation: {
                let runner = ProcessRunner.liveValue
                func run(_ arguments: [String]) async throws -> ProcessResult {
                    try await runner.runOrThrow(
                        executable: tmuxPath,
                        arguments: ["-S", socketPath, "-f", "/dev/null"] + arguments
                    )
                }
                _ = try await run([
                    "new-session", "-d", "-s", "fixture", "-x", "40", "-y", "12",
                    "/bin/sh -c 'stty raw -echo; printf CTRLX_READY; exec /bin/cat'",
                ])
                let tmux = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                let clients = TmuxControlClientManager(tmuxPath: tmuxPath, socketPath: socketPath)
                let streams = PaneStreamManager(
                    tmuxService: tmux, controlClientManager: clients, fifoDirectory: fifoDirectory
                )
                do {
                    let pane = try #require(await tmux.refreshPanes().first)
                    let fixture = Fixture(tmux: tmux, clients: clients, streams: streams, pane: pane,
                                          tmuxPath: tmuxPath, socketPath: socketPath)
                    try await fixture.waitForText("CTRLX_READY")
                    try await operation(fixture)
                } catch {
                    await streams.disconnectAll()
                    await clients.disconnectAll()
                    _ = try? await run(["kill-server"])
                    throw error
                }
                await streams.disconnectAll()
                await clients.disconnectAll()
                _ = try await run(["kill-server"])
            }
        }

        @MainActor
        private struct Fixture {
            let tmux: TmuxService
            let clients: TmuxControlClientManager
            let streams: PaneStreamManager
            let pane: PaneInfo
            let tmuxPath: String
            let socketPath: String

            func controlClientCount() async throws -> Int {
                let result = try await ProcessRunner.liveValue.runOrThrow(
                    executable: tmuxPath,
                    arguments: ["-S", socketPath, "list-clients", "-F", "#{client_control_mode}"]
                )
                return result.stdoutString.split(separator: "\n").filter { $0 == "1" }.count
            }

            func write(_ text: String) async throws {
                try await tmux.sendRawBytes(pane.paneId, data: Data(text.utf8))
                try await waitForText(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            func visibleText() async throws -> String {
                try await tmux.capturePaneText(pane.paneId).trimmingCharacters(in: .newlines)
            }

            func waitForText(_ text: String) async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                repeat {
                    if try await visibleText().contains(text) { return }
                    try await Task.sleep(for: .milliseconds(10))
                } while ContinuousClock.now < deadline
                throw FixtureError.outputTimeout
            }
        }

        private enum FixtureError: Error { case outputTimeout }

        @MainActor
        private final class CapturedTerminal: TerminalDelegate {
            private lazy var terminal = Terminal(delegate: self)

            init(cols: Int, rows: Int) {
                terminal.resize(cols: cols, rows: rows)
            }

            func feed(_ data: Data) { terminal.feed(byteArray: Array(data)) }

            var cursorLine: String {
                terminal.getLine(row: terminal.buffer.y)?.translateToString(trimRight: true, skipNullCellsFollowingWide: true)
                    .trimmingCharacters(in: .whitespaces) ?? ""
            }

            var text: String {
                (0..<terminal.rows).compactMap { terminal.getLine(row: $0) }
                    .map {
                        $0.translateToString(trimRight: true, skipNullCellsFollowingWide: true)
                            .trimmingCharacters(in: .whitespaces)
                    }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .newlines)
            }

            nonisolated func send(source _: Terminal, data _: ArraySlice<UInt8>) { }
            nonisolated func showCursor(source _: Terminal) { }
            nonisolated func hideCursor(source _: Terminal) { }
            nonisolated func setTerminalTitle(source _: Terminal, title _: String) { }
            nonisolated func setTerminalIconTitle(source _: Terminal, title _: String) { }
            nonisolated func sizeChanged(source _: Terminal) { }
            nonisolated func scrolled(source _: Terminal, yDisp _: Int) { }
            nonisolated func hostCurrentDirectoryUpdated(source _: Terminal) { }
            nonisolated func hostCurrentDocumentUpdated(source _: Terminal) { }
        }
    }
#endif
