import CtrlxCommon
import Dependencies
import Foundation
import Testing
@testable import CtrlxServerFeature

@Suite("Tmux window reorder")
@MainActor
struct WindowReorderTests {
    private func pane(
        _ paneId: String,
        session: String,
        window: Int,
        stableId: String
    ) -> PaneInfo {
        PaneInfo(
            paneId: paneId,
            target: "\(session):\(window).0",
            sessionName: session,
            windowIndex: window,
            tmuxWindowId: stableId,
            paneIndex: 0,
            command: "zsh",
            currentPath: "/tmp",
            width: 80,
            height: 24,
            isActive: true
        )
    }

    @Test("Plans stable-id swaps without assuming a zero base index")
    func plansBaseIndexOneOrder() throws {
        let current = [
            TmuxService.WindowPosition(stableId: "@1", index: 1),
            TmuxService.WindowPosition(stableId: "@2", index: 2),
            TmuxService.WindowPosition(stableId: "@3", index: 3),
        ]

        let swaps = try TmuxService.windowReorderSwaps(
            current: current,
            desiredIds: ["@3", "@1", "@2"]
        )

        #expect(swaps == [
            TmuxService.WindowSwap(sourceId: "@3", targetIndex: 1),
            TmuxService.WindowSwap(sourceId: "@1", targetIndex: 2),
        ])
    }

    @Test("Preserves sparse tmux index slots")
    func preservesSparseIndices() throws {
        let current = [
            TmuxService.WindowPosition(stableId: "@4", index: 4),
            TmuxService.WindowPosition(stableId: "@8", index: 8),
            TmuxService.WindowPosition(stableId: "@12", index: 12),
        ]

        let swaps = try TmuxService.windowReorderSwaps(
            current: current,
            desiredIds: ["@8", "@12", "@4"]
        )

        #expect(swaps == [
            TmuxService.WindowSwap(sourceId: "@8", targetIndex: 4),
            TmuxService.WindowSwap(sourceId: "@12", targetIndex: 8),
        ])
    }

    @Test("Rejects stale, partial, and duplicate requests")
    func rejectsInvalidOrders() {
        let current = [
            TmuxService.WindowPosition(stableId: "@1", index: 1),
            TmuxService.WindowPosition(stableId: "@2", index: 2),
        ]

        for desired in [["@1"], ["@1", "@1"], ["@1", "@gone"]] {
            #expect(throws: TmuxError.self) {
                try TmuxService.windowReorderSwaps(current: current, desiredIds: desired)
            }
        }
    }

    @Test("Detects target changes without confusing linked sessions")
    func detectsReindexBySessionAndStableId() {
        let old = [
            pane("%1", session: "alpha", window: 1, stableId: "@7"),
            pane("%1", session: "beta", window: 4, stableId: "@7"),
            pane("%2", session: "alpha", window: 2, stableId: "@8"),
        ]
        let new = [
            pane("%1", session: "alpha", window: 2, stableId: "@7"),
            pane("%1", session: "beta", window: 4, stableId: "@7"),
            pane("%2", session: "alpha", window: 1, stableId: "@8"),
        ]

        #expect(WindowReindexMapping.detect(from: old, to: new) == [
            "alpha:1": "alpha:2",
            "alpha:2": "alpha:1",
        ])
    }

    @Test("Reorders a live tmux session without losing window identity")
    func reordersLiveSession() async throws {
        let tmuxPath = "/opt/homebrew/bin/tmux"
        try #require(FileManager.default.isExecutableFile(atPath: tmuxPath))

        try await withDependencies {
            $0[ProcessRunner.self] = .liveValue
        } operation: {
            let suffix = UUID().uuidString.lowercased()
            let sessionName = "ctrlx-reorder-\(suffix)"
            let socketPath = "/tmp/gw-\(suffix.prefix(8)).sock"
            let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
            defer { try? FileManager.default.removeItem(atPath: socketPath) }

            _ = try await service.createSession(baseName: sessionName, width: 80, height: 24)
            do {
                _ = try await service.newWindow(sessionName: sessionName, windowName: "second")
                _ = try await service.newWindow(sessionName: sessionName, windowName: "third")
                _ = await service.refreshPanes()

                let before = service.windows
                    .filter { $0.sessionName == sessionName }
                    .sorted { $0.windowIndex < $1.windowIndex }
                #expect(before.count == 3)
                #expect(before.allSatisfy { $0.stableId.hasPrefix("@") })

                let desired = [before[2].stableId, before[0].stableId, before[1].stableId]
                let originalPaneIds = Set(before.flatMap(\.panes).map(\.paneId))
                let originalIndices = before.map(\.windowIndex)
                let mapping = try await service.moveWindows(in: sessionName, to: desired)
                _ = await service.refreshPanes()

                let after = service.windows
                    .filter { $0.sessionName == sessionName }
                    .sorted { $0.windowIndex < $1.windowIndex }
                #expect(after.map(\.stableId) == desired)
                #expect(after.map(\.windowIndex) == originalIndices)
                #expect(Set(after.flatMap(\.panes).map(\.paneId)) == originalPaneIds)
                #expect(mapping.count == before.count)

                try await service.killSession(sessionName)
            } catch {
                try? await service.killSession(sessionName)
                throw error
            }
        }
    }
}
