import Foundation
import Testing
@testable import CtrlxNetworking

@Suite("PaneState stable window identity")
struct PaneStateStableIdentityTests {
    @Test("Stable tmux id survives a wire round trip")
    func roundTrip() throws {
        let original = PaneState(
            paneId: "%1",
            target: "work:2.0",
            sessionName: "work",
            windowIndex: 2,
            tmuxWindowId: "@7"
        )

        let decoded = try JSONDecoder().decode(PaneState.self, from: JSONEncoder().encode(original))
        #expect(decoded.tmuxWindowId == "@7")
        #expect(decoded.stableWindowId == "@7")
    }

    @Test("Snapshot from an older host falls back to session and index")
    func decodesLegacySnapshot() throws {
        let current = PaneState(
            paneId: "%1",
            target: "work:2.0",
            sessionName: "work",
            windowIndex: 2,
            tmuxWindowId: "@7"
        )
        let encoded = try JSONEncoder().encode(current)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "tmuxWindowId")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(PaneState.self, from: legacy)
        #expect(decoded.tmuxWindowId == nil)
        #expect(decoded.stableWindowId == "work:2")
    }
}
