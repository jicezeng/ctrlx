// Compile with the production networking models; never duplicate their wire types here.
import Foundation

@main
struct AgentSkillWireExamples {
    static func main() throws {
        let context = APIIdentifyInfo(
            session: APISessionInfo(id: "work", name: "work", windowCount: 1, isAttached: true),
            window: APIWindowInfo(
                id: "work:0", index: 0, name: "build", paneCount: 1,
                isActive: true, sessionId: "work"
            ),
            pane: APIPaneInfo(
                id: "%3", index: 0, isActive: true, command: "claude", cwd: "/path/to/project",
                width: 120, height: 40, windowId: "work:0", hasAgentSession: true
            )
        )
        let examples: [String: JSONValue] = [
            "identify": .object(context.toJSONValue()),
            "ack": try JSONValue(encoding: JSONRPCResponse.ok(id: "request-1")),
            "permission_decisions": try JSONValue(encoding: [
                PermissionDecision.allow, .deny, .denyWithFeedback("use tabs instead"),
            ]),
            "plan_decisions": try JSONValue(encoding: [PlanDecision.approve, .reject]),
        ]
        FileHandle.standardOutput.write(try JSONEncoder().encode(examples))
    }
}
