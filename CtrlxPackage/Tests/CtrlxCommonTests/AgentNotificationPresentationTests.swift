import CtrlxNetworking
import Testing
@testable import CtrlxCommon

@Suite("Agent notification presentation")
struct AgentNotificationPresentationTests {
    @Test("Uses tmux context and removes a repeated project prefix")
    func tmuxContext() {
        let pane = PaneState(
            paneId: "%1",
            sessionName: "coding",
            windowName: "agent",
            agentSession: AgentSession(
                paneId: "%1",
                detectedProjectPath: "/Users/me/Projects/coding"
            )
        )

        let presentation = AgentNotificationPresentation(
            title: "Session Idle",
            body: "coding: Finished the change",
            paneState: pane
        )

        #expect(presentation.title == "coding · agent")
        #expect(presentation.subtitle == "Finished")
        #expect(presentation.body == "Finished the change")
    }

    @Test("Preserves an explicit status and falls back to the session name")
    func explicitStatus() {
        let pane = PaneState(paneId: "%1", sessionName: "coding")
        let presentation = AgentNotificationPresentation(
            title: "Codex wants answers",
            subtitle: "Needs input",
            body: "coding: Choose an option",
            paneState: pane
        )

        #expect(presentation.title == "coding")
        #expect(presentation.subtitle == "Needs input")
        #expect(presentation.body == "Choose an option")
    }

    @Test("Keeps legacy copy when pane metadata is unavailable")
    func missingPaneMetadata() {
        let presentation = AgentNotificationPresentation(
            title: "Session Idle",
            body: "coding: Finished the change",
            paneState: nil
        )

        #expect(presentation.title == "Session Idle")
        #expect(presentation.subtitle == nil)
        #expect(presentation.body == "coding: Finished the change")
    }

    @Test("Bounds contextual copy for the encrypted APNs envelope")
    func boundsContextCopy() {
        let pane = PaneState(
            paneId: "%1",
            sessionName: String(repeating: "会话", count: 100),
            windowName: String(repeating: "窗口", count: 100)
        )
        let presentation = AgentNotificationPresentation(
            title: String(repeating: "状态", count: 100),
            body: "Result",
            paneState: pane
        )

        #expect(presentation.title.utf8.count <= NotificationContent.maximumContextTitleBytes)
        #expect(presentation.title.hasSuffix("…"))
        #expect(
            presentation.subtitle?.utf8.count ?? 0
                <= NotificationContent.maximumContextSubtitleBytes
        )
        #expect(presentation.subtitle?.hasSuffix("…") == true)
    }
}
