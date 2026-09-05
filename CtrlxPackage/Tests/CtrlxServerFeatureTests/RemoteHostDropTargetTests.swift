#if os(macOS)
    import Foundation
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Remote host drop target")
    struct RemoteHostDropTargetTests {
        private let frames = [
            "a": CGRect(x: 0, y: 0, width: 200, height: 30),
            "b": CGRect(x: 0, y: 40, width: 200, height: 30),
            "c": CGRect(x: 0, y: 80, width: 200, height: 30),
        ]

        @Test("Resolves another host header")
        func resolvesTarget() {
            #expect(target(at: CGPoint(x: 100, y: 55), source: "a") == "b")
            #expect(target(at: CGPoint(x: 100, y: 95), source: "a") == "c")
        }

        @Test("Uses bounded tolerance and ignores invalid locations")
        func usesBoundedTolerance() {
            #expect(target(at: CGPoint(x: 100, y: 15), source: "a") == nil)
            #expect(target(at: CGPoint(x: 100, y: 76), source: "a") == "c")
            #expect(target(at: CGPoint(x: 100, y: 150), source: "a") == nil)
            #expect(target(at: CGPoint(x: 220, y: 55), source: "a") == nil)
        }

        @Test("Uses visible host order and ignores unlisted frames")
        func ignoresUnlistedFrames() {
            #expect(RemoteHostDropTarget.hostID(
                at: CGPoint(x: 100, y: 55),
                orderedHostIDs: ["a", "c"],
                headerFrames: frames,
                excluding: "a"
            ) == "c")
        }

        private func target(at location: CGPoint, source: String) -> String? {
            RemoteHostDropTarget.hostID(
                at: location,
                orderedHostIDs: ["a", "b", "c"],
                headerFrames: frames,
                excluding: source
            )
        }
    }
#endif
