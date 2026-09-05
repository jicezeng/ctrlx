#if os(macOS)
    import CtrlxNetworking

    /// Builds the Host→Viewer pane snapshot without refreshing tmux or mutating
    /// either observable Host model. Topology refresh and UI publication belong
    /// to the existing discovery paths; a Viewer read must stay a read.
    @MainActor
    enum HostSessionStateSnapshot {
        static func make(
            windowManager: MirrorWindowManager,
            editorManager: EditorSessionManager
        ) -> [String: PaneState] {
            var paneStates = windowManager.paneStates
            for (paneId, var state) in paneStates {
                state.editorSession = editorManager.editorSessionInfo(for: paneId)
                paneStates[paneId] = state
            }
            return paneStates
        }
    }
#endif
