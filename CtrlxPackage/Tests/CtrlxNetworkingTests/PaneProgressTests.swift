import Testing
@testable import CtrlxNetworking

@Suite("Effective session progress")
struct PaneProgressTests {
    @Test("A session without terminal progress or a working agent has no bar")
    func noProgress() {
        let panes = [
            PaneState(paneId: "%1"),
            PaneState(
                paneId: "%2",
                agentSession: AgentSession(paneId: "%2", pluginID: "codex", state: .idle)
            ),
        ]

        #expect(panes.effectiveProgress == nil)
    }

    @Test("A working agent supplies indeterminate progress")
    func workingAgentFallback() {
        let panes = [
            PaneState(
                paneId: "%1",
                agentSession: AgentSession(paneId: "%1", pluginID: "codex", state: .working)
            ),
        ]

        #expect(panes.effectiveProgress == .indeterminate)
    }

    @Test("Only an agent working state enables the fallback")
    func nonWorkingStatesDoNotFallback() {
        let panes = [
            PaneState(
                paneId: "%1",
                agentSession: AgentSession(
                    paneId: "%1",
                    state: .awaitingPermission(
                        PermissionRequest(title: "Bash", description: "ls"),
                        requestID: "request"
                    )
                )
            ),
            PaneState(paneId: "%2", cliSessionState: .working),
        ]

        #expect(panes.effectiveProgress == nil)
    }

    @Test("Real terminal progress wins over an earlier working-agent fallback")
    func terminalProgressWinsAcrossPanes() {
        let panes = [
            PaneState(
                paneId: "%1",
                agentSession: AgentSession(paneId: "%1", pluginID: "codex", state: .working)
            ),
            PaneState(paneId: "%2", progress: .normal(42)),
        ]

        #expect(panes.effectiveProgress == .normal(42))
    }

    @Test("The first real terminal progress keeps the existing pane-order winner")
    func firstTerminalProgressWins() {
        let panes = [
            PaneState(paneId: "%1", progress: .warning),
            PaneState(paneId: "%2", progress: .error),
        ]

        #expect(panes.effectiveProgress == .warning)
    }
}
