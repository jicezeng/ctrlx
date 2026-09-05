import Foundation
import Testing
@testable import CtrlxCommon

@Suite("Remote session order")
struct RemoteSessionOrderTests {
    @Test("Stored names rank known sessions and append new sessions in host order")
    func appliesStoredOrder() {
        let hostOrder = ["beta", "alpha", "new-two", "new-one"]

        let ordered = RemoteSessionOrder.applying(
            ["stale", "alpha", "alpha", "beta"],
            to: hostOrder,
            sessionName: { $0 }
        )

        #expect(ordered == ["alpha", "beta", "new-two", "new-one"])
    }

    @Test("Empty preference preserves host order")
    func preservesHostOrder() {
        let hostOrder = ["beta", "alpha"]
        #expect(RemoteSessionOrder.applying([], to: hostOrder, sessionName: { $0 }) == hostOrder)
    }

    @Test("Move coordinates match collection move semantics")
    func movesRows() {
        let names = ["a", "b", "c", "d"]

        #expect(RemoteSessionOrder.moving(names, fromOffsets: [1], toOffset: 4) == ["a", "c", "d", "b"])
        #expect(RemoteSessionOrder.moving(names, fromOffsets: [3], toOffset: 1) == ["a", "d", "b", "c"])
        #expect(RemoteSessionOrder.moving(names, fromOffsets: [1, 2], toOffset: 4) == ["a", "d", "b", "c"])
    }

    @Test("Invalid move is ignored")
    func ignoresInvalidMove() {
        let names = ["a", "b"]
        #expect(RemoteSessionOrder.moving(names, fromOffsets: [7], toOffset: 0) == names)
    }

    @Test("Rename preserves rank without creating duplicates")
    func replacesRenamedSession() {
        #expect(RemoteSessionOrder.replacing("old", with: "new", in: ["a", "old", "b"]) == ["a", "new", "b"])
        #expect(RemoteSessionOrder.replacing("old", with: "new", in: ["old", "new"]) == ["new"])
    }

    @Test("Normalization removes empty and duplicate names")
    func normalizesNames() {
        #expect(RemoteSessionOrder.normalized(["a", "", "b", "a"]) == ["a", "b"])
    }
}
