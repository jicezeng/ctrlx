import Testing
@testable import CtrlxFeature

@Suite("Terminal input document synchronizer")
struct TerminalInputProxyViewTests {
    @Test("Appending text only inserts the new suffix")
    func append() {
        var synchronizer = TerminalInputDocumentSynchronizer()

        #expect(synchronizer.advance(to: "好的") == TerminalInputDocumentDelta(
            deletionCount: 0,
            insertion: "好的"
        ))
        #expect(synchronizer.advance(to: "好的，我知道了") == TerminalInputDocumentDelta(
            deletionCount: 0,
            insertion: "，我知道了"
        ))
    }

    @Test("Recognition correction rewrites only the changed suffix")
    func correction() {
        var synchronizer = TerminalInputDocumentSynchronizer()
        _ = synchronizer.advance(to: "这是语音输人")

        #expect(synchronizer.advance(to: "这是语音输入") == TerminalInputDocumentDelta(
            deletionCount: 1,
            insertion: "入"
        ))
    }

    @Test("Deletion counts user-visible characters")
    func graphemeDeletion() {
        var synchronizer = TerminalInputDocumentSynchronizer()
        _ = synchronizer.advance(to: "测试👨‍👩‍👧‍👦")

        #expect(synchronizer.advance(to: "测试") == TerminalInputDocumentDelta(
            deletionCount: 1,
            insertion: ""
        ))
    }

    @Test("Reset starts a fresh terminal input line")
    func reset() {
        var synchronizer = TerminalInputDocumentSynchronizer()
        _ = synchronizer.advance(to: "first line")
        synchronizer.reset()

        #expect(synchronizer.advance(to: "next") == TerminalInputDocumentDelta(
            deletionCount: 0,
            insertion: "next"
        ))
    }

    @Test("A fresh voice document does not delete separately typed input")
    func freshVoiceDocument() {
        var synchronizer = TerminalInputDocumentSynchronizer()
        _ = synchronizer.advance(to: "first recording")
        synchronizer.reset()

        #expect(synchronizer.advance(to: "new") == TerminalInputDocumentDelta(
            deletionCount: 0,
            insertion: "new"
        ))
        #expect(synchronizer.advance(to: "new phrase") == TerminalInputDocumentDelta(
            deletionCount: 0,
            insertion: " phrase"
        ))
    }
}
