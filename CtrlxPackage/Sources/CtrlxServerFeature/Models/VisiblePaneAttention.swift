import CtrlxCommon
import CtrlxNetworking

/// Read acknowledgements belong to a displayed pane, not the selected left
/// window or a global pending count. Remote pane IDs are scoped to their host.
enum VisiblePaneAttention: Equatable, Sendable {
    case local(paneId: String)
    case remote(hostId: String, paneId: String)

    @MainActor
    func state(windowManager: MirrorWindowManager, remoteStore: SessionStore?) -> AgentState? {
        switch self {
        case let .local(paneId):
            windowManager.paneStates[paneId]?.agentSession?.state
        case let .remote(hostId, paneId):
            remoteStore?.paneStates[PaneKey(pairId: hostId, paneId: paneId)]?.agentSession?.state
        }
    }

    /// Mutate synchronously, before any network work, so overlapping views or
    /// activation/state callbacks cannot acknowledge the same completion twice.
    /// Re-read the store: the observed completion may already have advanced to
    /// a new turn or a blocking form by the time the callback runs.
    @MainActor
    func markHandledIfNeeded(
        isVisible: Bool,
        isAppActive: Bool,
        windowManager: MirrorWindowManager,
        remoteStore: SessionStore?
    ) -> Bool {
        guard isVisible, isAppActive,
              case .doneWorking = state(windowManager: windowManager, remoteStore: remoteStore)
        else { return false }

        switch self {
        case let .local(paneId):
            windowManager.markSessionHandled(paneId: paneId)
        case let .remote(hostId, paneId):
            remoteStore?.markSessionHandled(paneId: paneId, hostId: hostId)
        }
        return true
    }
}
