import ClaudeSpyCommon
import Dependencies
import Foundation
import Testing
@testable import ClaudeSpyServerFeature

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
                let sourcePanes = await service.refreshPanes()
                let sourcePane = try #require(
                    sourcePanes.first { $0.paneId == created.paneId }
                )

                let inheritedPaneID = try await service.splitPane(
                    created.paneId,
                    horizontal: true
                )
                let inheritedPanes = await service.refreshPanes()
                let inheritedPane = try #require(
                    inheritedPanes.first { $0.paneId == inheritedPaneID }
                )
                #expect(inheritedPane.currentPath == sourcePane.currentPath)

                let overriddenPaneID = try await service.splitPane(
                    created.paneId,
                    horizontal: false,
                    workingDirectory: overrideURL.path
                )
                let overriddenPanes = await service.refreshPanes()
                let overriddenPane = try #require(
                    overriddenPanes.first { $0.paneId == overriddenPaneID }
                )
                #expect(
                    URL(fileURLWithPath: overriddenPane.currentPath).resolvingSymlinksInPath()
                        == overrideURL.resolvingSymlinksInPath()
                )

                try await service.killSession(created.sessionName)
            } catch {
                try? await service.killSession(created.sessionName)
                throw error
            }
        }
    }
}
