#if os(macOS)
    import Foundation
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Pane subscription bootstrap")
    struct PaneSubscriptionBootstrapTests {
        @Test("Bytes already represented by the snapshot are not replayed")
        func preBoundaryBytesAreDiscarded() {
            var bootstrap = PaneSubscriptionBootstrap()

            #expect(bootstrap.route(Data("overlap-1".utf8)) == nil)
            #expect(bootstrap.route(Data("overlap-2".utf8)) == nil)
            bootstrap.markSnapshotBoundary()

            let initial = bootstrap.finish(with: Data("snapshot".utf8))

            #expect(String(decoding: initial, as: UTF8.self) == "snapshot")
            #expect(!bootstrap.isCollecting)
        }

        @Test("Only post-boundary bytes follow the authoritative snapshot")
        func postBoundaryBytesAreBuffered() {
            var bootstrap = PaneSubscriptionBootstrap()

            #expect(bootstrap.route(Data("before-capture".utf8)) == nil)
            bootstrap.markSnapshotBoundary()
            #expect(bootstrap.route(Data("after-capture".utf8)) == nil)
            let initial = bootstrap.finish(with: Data("snapshot-".utf8))
            let live = bootstrap.route(Data("live".utf8))

            #expect(String(decoding: initial, as: UTF8.self) == "snapshot-after-capture")
            #expect(String(decoding: live ?? Data(), as: UTF8.self) == "live")
        }

        @Test("A duplicated non-idempotent erase is excluded from bootstrap")
        func overlappingEraseIsExcluded() {
            var bootstrap = PaneSubscriptionBootstrap()
            let eraseDisplay = Data([0x1B, 0x5B, 0x32, 0x4A])

            #expect(bootstrap.route(eraseDisplay) == nil)
            bootstrap.markSnapshotBoundary()
            let initial = bootstrap.finish(with: Data("complete-screen".utf8))

            #expect(initial == Data("complete-screen".utf8))
        }
    }
#endif
