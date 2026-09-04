#if os(macOS)
    import Foundation
    import Testing
    @testable import ClaudeSpyServerFeature

    @Suite("Pane subscription bootstrap")
    struct PaneSubscriptionBootstrapTests {
        @Test("Capture-time increments cannot overtake the initial snapshot")
        func snapshotAlwaysComesFirst() {
            var bootstrap = PaneSubscriptionBootstrap()

            #expect(bootstrap.route(Data("new-1".utf8)) == nil)
            #expect(bootstrap.route(Data("new-2".utf8)) == nil)

            let initial = bootstrap.finish(with: Data("snapshot-".utf8))

            #expect(String(decoding: initial, as: UTF8.self) == "snapshot-new-1new-2")
            #expect(!bootstrap.isCollecting)
        }

        @Test("No capture-time increment is lost before a subscriber becomes live")
        func captureGapIsBuffered() {
            var bootstrap = PaneSubscriptionBootstrap()

            #expect(bootstrap.route(Data("during-capture".utf8)) == nil)
            let initial = bootstrap.finish(with: Data("snapshot-".utf8))
            let live = bootstrap.route(Data("after-capture".utf8))

            #expect(String(decoding: initial, as: UTF8.self) == "snapshot-during-capture")
            #expect(String(decoding: live ?? Data(), as: UTF8.self) == "after-capture")
        }
    }
#endif
