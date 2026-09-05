@testable import CtrlxCommon
import Testing

@Suite("OSC 8 payload detection")
struct OSC8PayloadDetectorTests {
    @Test("Detects linked text after ESC and C1 openers")
    func linkedText() {
        var detector = OSC8PayloadDetector()

        let escapedLinkDetected = detector.mayContainNewPayload(
            in: Array("\u{1B}]8;;https://example.com\u{07}link".utf8)[...]
        )
        #expect(escapedLinkDetected)

        var c1Detector = OSC8PayloadDetector()
        let c1LinkDetected = c1Detector.mayContainNewPayload(
            in: [0x9D, 0x38, 0x3B, 0x3B, 0x75, 0x9C, 0x78][...]
        )
        #expect(c1LinkDetected)
    }

    @Test("Detects an ESC opener at every chunk boundary")
    func splitEscapeOpener() {
        let opener = Array("\u{1B}]8;".utf8)

        for splitIndex in 1..<opener.count {
            var detector = OSC8PayloadDetector()
            let remainder = Array(opener[splitIndex...]) + Array(";url\u{07}".utf8)
            let partialDetected = detector.mayContainNewPayload(in: opener[..<splitIndex])
            let openerDetected = detector.mayContainNewPayload(in: remainder[...])
            let linkedTextDetected = detector.mayContainNewPayload(in: Array("x".utf8)[...])
            #expect(!partialDetected)
            #expect(!openerDetected)
            #expect(linkedTextDetected)
        }
    }

    @Test("Stops scanning after the closing sequence")
    func closingSequence() {
        var detector = OSC8PayloadDetector()
        _ = detector.mayContainNewPayload(
            in: Array("\u{1B}]8;;url\u{07}x".utf8)[...]
        )

        let closingDetected = detector.mayContainNewPayload(
            in: Array("\u{1B}]8;;\u{07}".utf8)[...]
        )
        let trailingTextDetected = detector.mayContainNewPayload(
            in: Array("plain text".utf8)[...]
        )
        #expect(closingDetected)
        #expect(!trailingTextDetected)
    }

    @Test("Ignores ordinary animation and unrelated OSC sequences")
    func ignoresOtherOutput() {
        var detector = OSC8PayloadDetector()

        let animationDetected = detector.mayContainNewPayload(
            in: Array("\u{1B}[2Kworking\r".utf8)[...]
        )
        let titleDetected = detector.mayContainNewPayload(
            in: Array("\u{1B}]2;title\u{07}".utf8)[...]
        )
        let plainTextDetected = detector.mayContainNewPayload(
            in: Array("plain 8; text".utf8)[...]
        )
        #expect(!animationDetected)
        #expect(!titleDetected)
        #expect(!plainTextDetected)
    }

    @Test("Recovers from a mismatched prefix")
    func recoversFromMismatch() {
        var detector = OSC8PayloadDetector()
        let bytes = Array("\u{1B}]2;x\u{1B}]8;;url\u{07}x".utf8)

        let detected = detector.mayContainNewPayload(in: bytes[...])
        #expect(detected)
    }
}
