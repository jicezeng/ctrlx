import CtrlxNetworking
import Foundation

public extension TerminalOnlySession {
    /// The menu-row label for a terminal-only session. The real tmux session
    /// name always leads so rename results stay visible; description/path are
    /// optional context and never replace the session identity.
    func displayTitle(homeDirectory: String?) -> String {
        if let customDescription, !customDescription.isEmpty {
            return "\(sessionName) — \(customDescription)"
        }
        if let currentPath, !currentPath.isEmpty {
            return "\(sessionName) — \(currentPath.abbreviatedPath(home: homeDirectory))"
        }
        return sessionName
    }
}
