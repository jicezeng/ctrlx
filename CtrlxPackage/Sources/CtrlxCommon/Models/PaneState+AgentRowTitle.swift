import CtrlxNetworking
import Foundation

public extension PaneState {
    /// The menu-row title for an agent-owning pane. The tmux session name is
    /// the stable identity and always leads; description/project information
    /// is appended only as context. `nil` for a plain terminal.
    var agentRowTitle: String? {
        guard let agentSession else { return nil }
        guard !sessionName.isEmpty else { return agentSession.displayName }

        let detail = if let customDescription, !customDescription.isEmpty {
            customDescription
        } else {
            agentSession.displayName
        }
        return detail == sessionName ? sessionName : "\(sessionName) — \(detail)"
    }
}
