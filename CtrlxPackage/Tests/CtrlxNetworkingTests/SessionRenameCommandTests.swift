import Foundation
import Testing
@testable import CtrlxNetworking

@Suite("RenameTmuxSession command")
struct SessionRenameCommandTests {
    @Test("Command type wraps and round-trips the rename spec")
    func codableRoundTrip() throws {
        let spec = RenameTmuxSession(sessionName: "old name", newName: "new name")
        #expect(spec.commandType == .renameTmuxSession(spec))

        let encoded = try JSONEncoder().encode(spec.commandType)
        let decoded = try JSONDecoder().decode(CommandType.self, from: encoded)
        #expect(decoded == .renameTmuxSession(spec))
        #expect(decoded.requiresResponse)
    }
}
