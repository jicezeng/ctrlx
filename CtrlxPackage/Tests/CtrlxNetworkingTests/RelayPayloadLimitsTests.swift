import CtrlxEncryption
import CtrlxNetworking
import Foundation
import Testing

@Suite("Relay payload limits")
struct RelayPayloadLimitsTests {
    @Test("Maximum dropped-file payload fits the encrypted Relay frame")
    func maximumDroppedFilePayloadFitsEncryptedFrame() throws {
        let file = DroppedFile(
            name: "pasted-image-00000000-0000-0000-0000-000000000000.jpg",
            data: Data(repeating: 0xA5, count: SendDroppedFiles.maxRawBytes)
        )
        let command = CommandMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            paneId: "%123",
            command: SendDroppedFiles(files: [file]).commandType,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(WebSocketMessage.command(command))

        // ChaChaPoly combined representation adds a 12-byte nonce and 16-byte tag.
        let encrypted = WebSocketMessage.encrypted(
            EncryptedWebSocketMessage(
                payload: EncryptedPayload(
                    ciphertext: Data(count: plaintext.count + 28),
                    senderKeyId: "00000000-0000-0000-0000-000000000002"
                )
            )
        )
        let frame = try encoder.encode(encrypted)

        #expect(frame.count <= RelayPayloadLimits.maxWebSocketFrameBytes)
    }
}
