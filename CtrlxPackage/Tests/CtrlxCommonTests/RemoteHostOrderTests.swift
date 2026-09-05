import CtrlxCommon
import Testing

@Suite("Remote host order")
struct RemoteHostOrderTests {
    @Test("Moves downward after the target")
    func movesDownward() {
        #expect(move(["a", "b", "c", "d"], source: "a", target: "c") == ["b", "c", "a", "d"])
        #expect(move(["a", "b", "c", "d"], source: "a", target: "d") == ["b", "c", "d", "a"])
    }

    @Test("Moves upward before the target")
    func movesUpward() {
        #expect(move(["a", "b", "c", "d"], source: "d", target: "b") == ["a", "d", "b", "c"])
        #expect(move(["a", "b", "c", "d"], source: "d", target: "a") == ["d", "a", "b", "c"])
    }

    @Test("Ignores invalid and self drops")
    func ignoresInvalidDrops() {
        let hosts = ["a", "b", "c"]
        #expect(move(hosts, source: "a", target: "a") == hosts)
        #expect(move(hosts, source: "missing", target: "b") == hosts)
        #expect(move(hosts, source: "a", target: "missing") == hosts)
    }

    @Test("Move coordinates match native list semantics")
    func movesListRows() {
        let hosts = ["a", "b", "c", "d"]
        #expect(RemoteHostOrder.moving(hosts, fromOffsets: [1], toOffset: 4) == ["a", "c", "d", "b"])
        #expect(RemoteHostOrder.moving(hosts, fromOffsets: [3], toOffset: 1) == ["a", "d", "b", "c"])
        #expect(RemoteHostOrder.moving(hosts, fromOffsets: [1, 2], toOffset: 4) == ["a", "d", "b", "c"])
        #expect(RemoteHostOrder.moving(hosts, fromOffsets: [9], toOffset: 0) == hosts)
    }

    private func move(_ hosts: [String], source: String, target: String) -> [String] {
        RemoteHostOrder.moving(hosts, sourceID: source, targetID: target, id: { $0 })
    }
}
