import CtrlxNetworking

/// Window- and pane-scoped values shown for a session's active terminal.
/// Session-scoped values such as description, color, and agent state are kept
/// separate because they intentionally aggregate across every window.
public struct ActiveWindowMetadata: Equatable, Sendable {
    public let windowName: String?
    public let terminalTitle: String?
    public let command: String?
    public let currentPath: String?
    public let gitBranch: String?

    public init(
        windowName: String?,
        terminalTitle: String?,
        command: String?,
        currentPath: String?,
        gitBranch: String?
    ) {
        self.windowName = windowName
        self.terminalTitle = terminalTitle
        self.command = command
        self.currentPath = currentPath
        self.gitBranch = gitBranch
    }
}

public extension TmuxSession {
    /// Metadata for the active pane in the active window. Never borrows values
    /// from an inactive sibling merely because that sibling has a non-empty title.
    var activeWindowMetadata: ActiveWindowMetadata {
        let window = activeWindow
        let pane = window?.activePane
        return ActiveWindowMetadata(
            windowName: window?.windowName,
            terminalTitle: pane?.terminalTitle,
            command: pane?.command,
            currentPath: pane?.currentPath,
            gitBranch: pane?.gitBranch
        )
    }
}
