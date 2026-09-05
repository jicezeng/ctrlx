import CtrlxNetworking
import Foundation
import Testing

@Suite("Terminal stream resynchronization message")
struct TerminalStreamResyncTests {
    @Test("Reset state survives JSON round trip")
    func resetStateRoundTrip() throws {
        let original = TerminalStreamMessage.resetState(
            paneId: "%7",
            width: 120,
            height: 40,
            content: Data([0x1B, 0x5B, 0x32, 0x4A]),
            scrollbackLineLimit: 10_000
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalStreamMessage.self, from: data)

        #expect(decoded.paneId == "%7")
        guard case let .resetState(snapshot) = decoded.updateType else {
            Issue.record("Expected resetState")
            return
        }
        #expect(snapshot.width == 120)
        #expect(snapshot.height == 40)
        #expect(snapshot.content == Data([0x1B, 0x5B, 0x32, 0x4A]))
        #expect(snapshot.scrollbackLineLimit == 10_000)
    }

    @Test("Older snapshots without a line limit remain decodable")
    func legacySnapshotRoundTrip() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","paneId":"%1","timestamp":0,"updateType":{"initialState":{"_0":{"width":80,"height":24,"contentBase64":""}}}}"#

        let decoded = try JSONDecoder().decode(TerminalStreamMessage.self, from: Data(json.utf8))

        guard case let .initialState(snapshot) = decoded.updateType else {
            Issue.record("Expected initialState")
            return
        }
        #expect(snapshot.scrollbackLineLimit == nil)
    }
}
