import CtrlxCommon
import Dependencies
import Foundation
import Testing
@testable import CtrlxServerFeature

@Suite("Tmux pane split")
@MainActor
struct TmuxPaneSplitTests {
    @Test("Window resize survives the targeted pane exiting")
    func resizeUsesStableWindowTarget() async throws {
        let tmuxPath = "/opt/homebrew/bin/tmux"
        try #require(FileManager.default.isExecutableFile(atPath: tmuxPath))

        try await withDependencies {
            $0[ProcessRunner.self] = .liveValue
        } operation: {
            let suffix = UUID().uuidString.lowercased()
            let sessionName = "ctrlx-resize-\(suffix)"
            let socketPath = "/tmp/gr-\(suffix.prefix(8)).sock"
            let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)
            defer { try? FileManager.default.removeItem(atPath: socketPath) }

            let created = try await service.createSession(
                baseName: sessionName,
                width: 120,
                height: 40
            )
            do {
                let exitingPaneID = try await service.splitPane(created.paneId, horizontal: true)
                let panes = await service.refreshPanes()
                let window = try #require(
                    LocalTmuxWindow.groupPanes(panes).first { $0.sessionName == created.sessionName }
                )
                #expect(window.stableId.hasPrefix("@"))

                try await service.killPane(exitingPaneID)
                try await service.resizePane(window.stableId, width: 100, height: 30)

                let remaining = await service.refreshPanes()
                    .filter { $0.sessionName == created.sessionName }
                #expect(remaining.count == 1)
                #expect(remaining.first?.width == 100)
                #expect(remaining.first?.height == 30)

                try await service.killSession(created.sessionName)
            } catch {
                try? await service.killSession(created.sessionName)
                throw error
            }
        }
    }

    @Test("A new pane inherits the target path unless explicitly overridden")
    func inheritsTargetPath() async throws {
        let tmuxPath = "/opt/homebrew/bin/tmux"
        try #require(FileManager.default.isExecutableFile(atPath: tmuxPath))

        try await withDependencies {
            $0[ProcessRunner.self] = .liveValue
        } operation: {
            let suffix = UUID().uuidString.lowercased()
            let sessionName = "ctrlx-split-\(suffix)"
            let socketPath = "/tmp/gs-\(suffix.prefix(8)).sock"
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ctrlx-split-\(suffix)", isDirectory: true)
            let sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
            let overrideURL = rootURL.appendingPathComponent("override", isDirectory: true)
            let service = TmuxService(tmuxPath: tmuxPath, socketPath: socketPath)

            try FileManager.default.createDirectory(
                at: sourceURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: overrideURL,
                withIntermediateDirectories: true
            )
            defer {
                try? FileManager.default.removeItem(at: rootURL)
                try? FileManager.default.removeItem(atPath: socketPath)
            }

            let created = try await service.createSession(
                baseName: sessionName,
                width: 120,
                height: 40,
                workingDirectory: sourceURL.path
            )
            do {
                let sourcePath = try await waitForCurrentPath(
                    of: created.paneId,
                    in: service,
                    expected: sourceURL
                )
                try #require(sourcePath == sourceURL.resolvingSymlinksInPath())

                let inheritedPaneID = try await service.splitPane(
                    created.paneId,
                    horizontal: true
                )
                let inheritedPath = try await waitForCurrentPath(
                    of: inheritedPaneID,
                    in: service,
                    expected: sourceURL
                )
                #expect(inheritedPath == sourcePath)

                let overriddenPaneID = try await service.splitPane(
                    created.paneId,
                    horizontal: false,
                    workingDirectory: overrideURL.path
                )
                let overriddenPath = try await waitForCurrentPath(
                    of: overriddenPaneID,
                    in: service,
                    expected: overrideURL
                )
                #expect(overriddenPath == overrideURL.resolvingSymlinksInPath())

                try await service.killSession(created.sessionName)
            } catch {
                try? await service.killSession(created.sessionName)
                throw error
            }
        }
    }

    /// tmux acknowledges a split before the child has necessarily completed
    /// exec. macOS may briefly report an empty/stale cwd during that transition.
    /// Wait for the observable path, then let the caller assert the exact result.
    private func waitForCurrentPath(
        of paneID: String,
        in service: TmuxService,
        expected: URL
    ) async throws -> URL? {
        let expectedPath = expected.resolvingSymlinksInPath()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let panes = await service.refreshPanes()
            let currentPath = panes.first { $0.paneId == paneID }
                .flatMap { pane -> URL? in
                    guard !pane.currentPath.isEmpty else { return nil }
                    return URL(fileURLWithPath: pane.currentPath).resolvingSymlinksInPath()
                }
            if currentPath == expectedPath || ContinuousClock.now >= deadline {
                return currentPath
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
