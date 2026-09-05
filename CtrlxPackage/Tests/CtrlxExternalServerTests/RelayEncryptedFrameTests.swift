import CtrlxEncryption
import Foundation
import Testing
@testable import CtrlxExternalServerLib

@Suite("Relay encrypted frame envelope")
struct RelayEncryptedFrameTests {
    @Test("Valid encrypted frame is accepted without rewriting its bytes")
    func validEncryptedFrame() throws {
        let original = Data(
            #"{ "payload" : { "payload" : { "version" : 1, "senderKeyId" : "key-1", "ciphertext" : "AQIDBA==" } }, "type" : "encrypted" }"#.utf8
        )

        let forwarded = try RelayMessageEnvelope.rawEncryptedFrame(
            in: original,
            using: JSONDecoder()
        )

        #expect(forwarded == original)
    }

    @Test("Invalid ciphertext alphabet is rejected")
    func invalidCiphertext() {
        let data = Data(
            #"{"type":"encrypted","payload":{"payload":{"ciphertext":"not base64!","senderKeyId":"key-1","version":1}}}"#.utf8
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RelayMessageEnvelope.self, from: data)
        }
    }

    @Test("Malformed base64 padding is rejected")
    func malformedPadding() {
        let data = Data(
            #"{"type":"encrypted","payload":{"payload":{"ciphertext":"A===","senderKeyId":"key-1","version":1}}}"#.utf8
        )

        #expect(throws: (any Error).self) {
            try RelayMessageEnvelope.rawEncryptedFrame(in: data, using: JSONDecoder())
        }
    }

    @Test("Non-encrypted messages stay on the typed decode path")
    func nonEncryptedEnvelope() throws {
        let data = Data(#"{"type":"ping"}"#.utf8)
        let forwarded = try RelayMessageEnvelope.rawEncryptedFrame(in: data, using: JSONDecoder())
        #expect(forwarded == nil)
    }
}
