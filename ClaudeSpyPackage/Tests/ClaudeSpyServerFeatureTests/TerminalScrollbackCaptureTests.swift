#if os(macOS)
    import ClaudeSpyCommon
    import Dependencies
    import Foundation
    import SwiftTerm
    import Testing
    @testable import ClaudeSpyServerFeature

    final private class ScrollbackTerminalDelegate: TerminalDelegate {
        func send(source _: Terminal, data _: ArraySlice<UInt8>) { }
        func showCursor(source _: Terminal) { }
        func hideCursor(source _: Terminal) { }
        func setTerminalTitle(source _: Terminal, title _: String) { }
        func setTerminalIconTitle(source _: Terminal, title _: String) { }
        func sizeChanged(source _: Terminal) { }
        func scrolled(source _: Terminal, yDisp _: Int) { }
        func hostCurrentDirectoryUpdated(source _: Terminal) { }
        func hostCurrentDocumentUpdated(source _: Terminal) { }
    }

    @Suite("Terminal scrollback capture")
    @MainActor
    struct TerminalScrollbackCaptureTests {
        @Test("Configured capture reaches beyond the old height multiplier")
        func capturesDeepHistoryFromRealTmux() async throws {
            let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
            let suffix = UUID().uuidString.lowercased().prefix(8)
            let socketPath = "/tmp/ctrlx-scrollback-\(suffix).sock"
            defer { killServer(tmuxPath: tmuxPath, socketPath: socketPath) }

            try await withDependencies {
                $0[ProcessRunner.self] = .liveValue
            } operation: {
                let tmux = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                let created = try await tmux.createSession(
                    baseName: "ctrlx-scrollback-\(suffix)",
                    width: 80,
                    height: 24,
                    runCommand: "jot -w CTRLX_SCROLLBACK_%04d 1200 1"
                )

                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                var fullText = ""
                repeat {
                    fullText = try await tmux.capturePaneText(created.paneId, scrollback: true)
                    if fullText.contains("CTRLX_SCROLLBACK_1200") { break }
                    await Task.yield()
                } while ContinuousClock.now < deadline
                #expect(fullText.contains("CTRLX_SCROLLBACK_1200"))

                let snapshot = try await tmux.capturePaneWithScrollbackForStreaming(
                    created.paneId,
                    scrollbackLineLimit: 1_000
                )
                let rendered = try #require(String(data: snapshot, encoding: .utf8))

                #expect(rendered.contains("CTRLX_SCROLLBACK_0300"))
                #expect(rendered.contains("CTRLX_SCROLLBACK_1200"))

                let delegate = ScrollbackTerminalDelegate()
                let terminal = Terminal(delegate: delegate)
                terminal.resize(cols: 80, rows: 24)
                terminal.changeScrollback(1_000)
                terminal.feed(byteArray: Array(snapshot))

                let retainedText = (0..<(terminal.buffer.yDisp + terminal.rows))
                    .compactMap { terminal.getScrollInvariantLine(row: $0) }
                    .map { $0.translateToString(trimRight: true) }
                    .joined(separator: "\n")
                #expect(retainedText.contains("CTRLX_SCROLLBACK_0300"))
                #expect(retainedText.contains("CTRLX_SCROLLBACK_1200"))
            }
        }

        private func killServer(tmuxPath: String, socketPath: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["-S", socketPath, "kill-server"]
            process.environment = [:]
            process.standardError = Pipe()
            process.standardOutput = Pipe()
            try? process.run()
        }
    }
#endif
