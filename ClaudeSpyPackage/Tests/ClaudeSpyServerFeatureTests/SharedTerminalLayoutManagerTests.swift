#if os(macOS)
    import ClaudeSpyCommon
    import ClaudeSpyNetworking
    import Dependencies
    import Testing
    @testable import ClaudeSpyServerFeature

    @MainActor
    @Suite("Host shared terminal layout store")
    struct SharedTerminalLayoutManagerTests {
        private func makeManager() -> MirrorWindowManager {
            withDependencies {
                $0[PreferencesService.self] = .inMemory()
                $0[ProcessRunner.self] = .previewValue
                $0[LoginItemService.self] = .previewValue
            } operation: {
                let tmux = TmuxService()
                let control = TmuxControlClientManager()
                return MirrorWindowManager(
                    settings: AppSettings(),
                    tmuxService: tmux,
                    paneStreamManager: PaneStreamManager(
                        tmuxService: tmux,
                        controlClientManager: control
                    ),
                    editorSessionManager: EditorSessionManager()
                )
            }
        }

        private func pane(id: String, windowId: String, windowIndex: Int) -> PaneInfo {
            PaneInfo(
                paneId: id,
                target: "coding:\(windowIndex).0",
                sessionName: "coding",
                windowIndex: windowIndex,
                tmuxWindowId: windowId,
                paneIndex: 0,
                command: "zsh",
                currentPath: "/tmp",
                width: 80,
                height: 24,
                isActive: true
            )
        }

        @Test("The Host clamps ratios, increments revisions, and ignores duplicates")
        func storesCanonicalLayout() {
            let manager = makeManager()

            #expect(manager.setSharedTerminalLayout(
                sessionName: "coding",
                leftWindowId: "@1",
                rightWindowIds: ["@2", "@3"],
                selectedRightWindowId: "@3",
                splitRatio: 1
            ))
            #expect(manager.sharedTerminalLayouts["coding"] == SharedTerminalLayout(
                leftWindowId: "@1",
                rightWindowIds: ["@2", "@3"],
                selectedRightWindowId: "@3",
                splitRatio: 0.85,
                revision: 1
            ))

            #expect(!manager.setSharedTerminalLayout(
                sessionName: "coding",
                leftWindowId: "@1",
                rightWindowIds: ["@2", "@3"],
                selectedRightWindowId: "@3",
                splitRatio: 0.85
            ))
            #expect(manager.setSharedTerminalLayout(
                sessionName: "coding",
                leftWindowId: "@2",
                rightWindowIds: [],
                selectedRightWindowId: nil,
                splitRatio: 0
            ))
            #expect(manager.sharedTerminalLayouts["coding"]?.revision == 2)
            #expect(manager.sharedTerminalLayouts["coding"]?.splitRatio == 0.15)
        }

        @Test("Invalid identities are rejected")
        func rejectsInvalidIdentity() {
            let manager = makeManager()

            #expect(!manager.setSharedTerminalLayout(
                sessionName: "",
                leftWindowId: "@1",
                rightWindowIds: [],
                selectedRightWindowId: nil,
                splitRatio: 0.5
            ))
            #expect(!manager.setSharedTerminalLayout(
                sessionName: "coding",
                leftWindowId: "@1",
                rightWindowIds: ["@1"],
                selectedRightWindowId: "@1",
                splitRatio: 0.5
            ))
            #expect(manager.sharedTerminalLayouts.isEmpty)
        }

        @Test("Dead windows are removed before a shared layout is published")
        func prunesDeadWindows() {
            let manager = makeManager()
            manager.updatePaneStates(from: [
                pane(id: "%1", windowId: "@1", windowIndex: 0),
                pane(id: "%2", windowId: "@2", windowIndex: 1),
            ])
            manager.setSharedTerminalLayout(
                sessionName: "coding",
                leftWindowId: "@1",
                rightWindowIds: ["@2"],
                selectedRightWindowId: "@2",
                splitRatio: 0.5
            )

            manager.updatePaneStates(from: [pane(id: "%1", windowId: "@1", windowIndex: 0)])

            #expect(manager.sharedTerminalLayouts["coding"] == SharedTerminalLayout(
                leftWindowId: "@1",
                rightWindowIds: [],
                selectedRightWindowId: nil,
                splitRatio: 0.5,
                revision: 2
            ))

            manager.updatePaneStates(from: [])

            #expect(manager.sharedTerminalLayouts.isEmpty)
        }
    }
#endif
