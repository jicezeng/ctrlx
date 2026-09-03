#if os(macOS)
    import ClaudeSpyCommon
    import ClaudeSpyNetworking
    import ConcurrencyExtras
    import Dependencies
    import Foundation
    import Testing
    @testable import ClaudeSpyServerFeature

    @MainActor
    @Suite("Remote resize ownership")
    struct RemoteResizeOwnershipTests {
        @Test("Host rejects a resize without an explicit user action")
        func hostRejectsAutomaticViewerResize() async {
            let commandID = UUID()
            let executor = TmuxCommandExecutor(
                tmuxService: TmuxService(
                    tmuxPath: "/nonexistent/tmux",
                    socketPath: "/tmp/ctrlx-unused.sock"
                )
            )
            let command = CommandMessage(
                id: commandID,
                paneId: "%1",
                command: ResizeTmuxPane(width: 80, height: 59).commandType
            )

            let response = await executor.execute(command)

            #expect(response.commandId == commandID)
            #expect(!response.success)
            #expect(response.error == "Terminal resize requires explicit user action")
        }

        @Test("Host executes an explicitly user-initiated resize")
        func hostExecutesManualViewerResize() async {
            let resizeArguments = LockIsolated<[String]?>(nil)

            await withDependencies {
                $0[ProcessRunner.self].run = { @Sendable _, arguments, _, _ in
                    if arguments.contains("resize-window") {
                        resizeArguments.withValue { $0 = arguments }
                        return ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
                    }
                    if arguments.contains("list-clients") {
                        return ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
                    }
                    if arguments.contains("list-panes") {
                        let separator = String(PaneInfo.fieldSeparator)
                        let paneLine = [
                            "%5", "work", "0", "0", "zsh", "/tmp",
                            "132", "48", "1", "zsh", "layout", "terminal 1",
                            "1", "", "", "", "@1",
                        ].joined(separator: separator)
                        return ProcessResult(
                            exitCode: 0,
                            stdout: Data("\(paneLine)\n".utf8),
                            stderr: Data()
                        )
                    }
                    return ProcessResult(
                        exitCode: 1,
                        stdout: Data(),
                        stderr: Data("unexpected command".utf8)
                    )
                }
            } operation: {
                let executor = TmuxCommandExecutor(
                    tmuxService: TmuxService(tmuxPath: "/usr/bin/tmux")
                )
                let commandID = UUID()
                let response = await executor.execute(CommandMessage(
                    id: commandID,
                    paneId: "@1",
                    command: ResizeTmuxPane(
                        width: 132,
                        height: 48,
                        userInitiated: true
                    ).commandType
                ))

                #expect(response.commandId == commandID)
                #expect(response.success)
                #expect(response.error == nil)
                let arguments = resizeArguments.value
                #expect(arguments != nil)
                #expect(arguments?.contains("@1") == true)
                #expect(arguments?.contains("132") == true)
                #expect(arguments?.contains("48") == true)
            }
        }
    }
#endif
