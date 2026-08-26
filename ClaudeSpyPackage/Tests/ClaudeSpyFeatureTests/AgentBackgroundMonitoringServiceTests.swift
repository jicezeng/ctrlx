#if os(iOS)
    import ClaudeSpyNetworking
    import Dependencies
    import Foundation
    import Testing
    @testable import ClaudeSpyFeature

    @MainActor
    @Suite("Agent background monitoring service")
    struct AgentBackgroundMonitoringServiceTests {
        @MainActor
        private final class Recorder {
            var startedIdentifiers: [String] = []
            var updates: [ContinuedProcessingUpdate] = []
            var finishedIdentifiers: [String] = []

            var client: ContinuedProcessingClient {
                ContinuedProcessingClient(
                    prepare: { },
                    start: { [self] request in
                        startedIdentifiers.append(request.identifier)
                        request.launchHandler()
                    },
                    update: { [self] _, update in
                        updates.append(update)
                    },
                    finish: { [self] identifier in
                        finishedIdentifiers.append(identifier)
                    }
                )
            }
        }

        private func makeService(
            recorder: Recorder
        ) -> AgentBackgroundMonitoringService {
            withDependencies {
                $0[ContinuedProcessingClient.self] = recorder.client
            } operation: {
                AgentBackgroundMonitoringService()
            }
        }

        private func status(
            hostId: String,
            paneId: String,
            state: AgentState
        ) -> AgentSessionStatusMessage {
            AgentSessionStatusMessage(
                pairId: hostId,
                sessionId: paneId,
                pluginId: "codex",
                state: state,
                timestamp: Date()
            )
        }

        @Test("The last terminal turn completes the shared system task")
        func lastTerminalTurnCompletesTask() {
            guard #available(iOS 26.0, *) else { return }
            let recorder = Recorder()
            let service = makeService(recorder: recorder)

            service.start(
                hostId: "home",
                paneId: "%1",
                sessionName: "one",
                windowName: "agent"
            )
            service.start(
                hostId: "office",
                paneId: "%2",
                sessionName: "two",
                windowName: "agent"
            )

            #expect(recorder.startedIdentifiers.count == 1)
            #expect(service.monitoringStatus == .active)

            service.handle(status(hostId: "home", paneId: "%1", state: .working)) { _ in }
            service.handle(status(hostId: "office", paneId: "%2", state: .working)) { _ in }
            service.handle(
                status(hostId: "home", paneId: "%1", state: .doneWorking(summary: nil))
            ) { _ in }

            #expect(recorder.finishedIdentifiers.isEmpty)
            #expect(service.monitoringStatus == .active)
            #expect(recorder.updates.last?.subtitle == "1 Agent working")

            service.handle(
                status(hostId: "office", paneId: "%2", state: .doneWorking(summary: nil))
            ) { _ in }

            #expect(recorder.finishedIdentifiers == recorder.startedIdentifiers)
            #expect(service.monitoringStatus == .inactive)
            #expect(recorder.updates.last?.subtitle == "Finished")
            #expect(
                recorder.updates.last?.completedUnitCount
                    == recorder.updates.last?.totalUnitCount
            )
        }

        @Test("Unrelated idle panes cannot keep a completed turn alive")
        func unrelatedIdleDoesNotKeepTaskAlive() {
            guard #available(iOS 26.0, *) else { return }
            let recorder = Recorder()
            let service = makeService(recorder: recorder)

            service.start(
                hostId: "home",
                paneId: "%1",
                sessionName: "one",
                windowName: "agent"
            )
            service.handle(status(hostId: "home", paneId: "%9", state: .idle)) { _ in }
            service.handle(
                status(hostId: "home", paneId: "%1", state: .doneWorking(summary: nil))
            ) { _ in }

            #expect(recorder.finishedIdentifiers.count == 1)
            #expect(service.monitoringStatus == .inactive)
        }

        @Test("Removing the only pending turn completes its task")
        func removingOnlyTurnCompletesTask() {
            guard #available(iOS 26.0, *) else { return }
            let recorder = Recorder()
            let service = makeService(recorder: recorder)

            service.start(
                hostId: "home",
                paneId: "%1",
                sessionName: "one",
                windowName: "agent"
            )
            service.removePane(hostId: "home", paneId: "%1")

            #expect(recorder.finishedIdentifiers.count == 1)
            #expect(service.monitoringStatus == .inactive)
            #expect(recorder.updates.last?.subtitle == "Monitoring ended")
        }
    }
#endif
