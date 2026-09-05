import Foundation
import Testing
@testable import CtrlxNetworking

@Suite("Remote resize command")
struct RemoteResizeCommandTests {
    @Test("Explicit user action survives the command wire format")
    func manualMarkerRoundTrips() throws {
        let command = ResizeTmuxPane(
            width: 132,
            height: 48,
            userInitiated: true
        ).commandType

        let decoded = try JSONDecoder().decode(
            CommandType.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test("Legacy resize payload decodes without user authorization")
    func legacyPayloadIsNotUserInitiated() throws {
        let command = try JSONDecoder().decode(
            ResizeTmuxPane.self,
            from: Data(#"{"width":80,"height":24}"#.utf8)
        )

        #expect(command.width == 80)
        #expect(command.height == 24)
        #expect(command.userInitiated == nil)
    }
}
