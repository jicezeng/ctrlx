#if os(macOS)
    import CtrlxCommon
    import Dependencies
    import Foundation
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Tmux terminal environment")
    @MainActor
    struct TmuxTerminalEnvironmentTests {
        @Test("A new session does not inherit NO_COLOR from the app")
        func clearsInheritedNoColor() async throws {
            let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
            let suffix = UUID().uuidString.lowercased()
            let socketPath = "/tmp/ctrlx-color-\(suffix.prefix(8)).sock"
            let sessionName = "ctrlx-color-\(suffix)"
            defer { killTmuxServer(tmuxPath: tmuxPath, socketPath: socketPath) }

            let liveRunner = ProcessRunner.liveValue
            let noColorRunner = ProcessRunner(
                run: { executable, arguments, environment, timeout in
                    var inheritedEnvironment = environment ?? [:]
                    inheritedEnvironment["NO_COLOR"] = "1"
                    return try await liveRunner.run(
                        executable,
                        arguments,
                        inheritedEnvironment,
                        timeout
                    )
                }
            )

            try await withDependencies {
                $0[ProcessRunner.self] = noColorRunner
                $0.continuousClock = ContinuousClock()
            } operation: {
                let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                let created = try await service.createSession(
                    baseName: sessionName,
                    width: 80,
                    height: 24
                )

                let globalEnvironment = try await liveRunner.run(
                    tmuxPath,
                    ["-S", socketPath, "show-environment", "-g", "NO_COLOR"],
                    nil,
                    5
                )
                #expect(!globalEnvironment.isSuccess)
                #expect(globalEnvironment.stderrString.contains("unknown variable"))

                try await service.killSession(created.sessionName)
            }
        }

        @Test("A new window clears stale session NO_COLOR")
        func newWindowClearsStaleNoColor() async throws {
            let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
            let suffix = UUID().uuidString.lowercased()
            let socketPath = "/tmp/ctrlx-window-color-\(suffix.prefix(8)).sock"
            let sessionName = "ctrlx-window-color-\(suffix)"
            defer { killTmuxServer(tmuxPath: tmuxPath, socketPath: socketPath) }

            let liveRunner = ProcessRunner.liveValue
            let created = try await liveRunner.run(
                tmuxPath,
                ["-S", socketPath, "new-session", "-d", "-s", sessionName],
                ["NO_COLOR": "1"],
                nil
            )
            try #require(created.isSuccess)

            try await withDependencies {
                $0[ProcessRunner.self] = liveRunner
                $0.continuousClock = ContinuousClock()
            } operation: {
                let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                _ = try await service.newWindow(sessionName: sessionName)

                let sessionEnvironment = try await liveRunner.run(
                    tmuxPath,
                    ["-S", socketPath, "show-environment", "-t", "=\(sessionName):", "NO_COLOR"],
                    nil,
                    5
                )
                #expect(!sessionEnvironment.isSuccess)
                #expect(sessionEnvironment.stderrString.contains("unknown variable"))
            }
        }

        @Test("A new pane clears stale session NO_COLOR")
        func splitPaneClearsStaleNoColor() async throws {
            let tmuxPath = try #require(TmuxBinaryLocator.liveValue.find())
            let suffix = UUID().uuidString.lowercased()
            let socketPath = "/tmp/ctrlx-pane-color-\(suffix.prefix(8)).sock"
            let sessionName = "ctrlx-pane-color-\(suffix)"
            defer { killTmuxServer(tmuxPath: tmuxPath, socketPath: socketPath) }

            let liveRunner = ProcessRunner.liveValue
            let created = try await liveRunner.run(
                tmuxPath,
                [
                    "-S", socketPath,
                    "new-session", "-d", "-s", sessionName,
                    ";",
                    "set-environment", "-t", "=\(sessionName):", "NO_COLOR", "1",
                    ";",
                    "display-message", "-p", "-t", "=\(sessionName):", "#{pane_id}",
                ],
                nil,
                nil
            )
            let paneId = created.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            try #require(created.isSuccess)
            try #require(!paneId.isEmpty)

            try await withDependencies {
                $0[ProcessRunner.self] = liveRunner
                $0.continuousClock = ContinuousClock()
            } operation: {
                let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
                _ = try await service.splitPane(paneId, horizontal: true)

                let sessionEnvironment = try await liveRunner.run(
                    tmuxPath,
                    ["-S", socketPath, "show-environment", "-t", "=\(sessionName):", "NO_COLOR"],
                    nil,
                    5
                )
                #expect(!sessionEnvironment.isSuccess)
                #expect(sessionEnvironment.stderrString.contains("unknown variable"))
            }
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
#endif
