@testable import ClaudeSpyFeature
import Testing

@Suite("Voice input text composer")
struct VoiceInputTextComposerTests {
    @Test("Uses the transcript for an empty draft")
    func emptyDraft() {
        #expect(VoiceInputTextComposer.appending("检查构建", to: "") == "检查构建")
    }

    @Test("Separates an existing draft from dictated text")
    func existingDraft() {
        #expect(
            VoiceInputTextComposer.appending("并安装到真机", to: "完成构建")
                == "完成构建 并安装到真机"
        )
    }

    @Test("Preserves existing trailing whitespace")
    func trailingWhitespace() {
        #expect(VoiceInputTextComposer.appending("--verbose", to: "xcodebuild ") == "xcodebuild --verbose")
    }

    @Test("Ignores an empty partial result")
    func emptyTranscript() {
        #expect(VoiceInputTextComposer.appending("  \n", to: "existing draft") == "existing draft")
    }
}

@Suite("Voice input transcript state")
struct VoiceInputTranscriptStateTests {
    @Test("Volatile results replace only the active phrase")
    func volatileResults() {
        var state = VoiceInputTranscriptState()

        #expect(state.receive("正在", isFinal: false) == "正在")
        #expect(state.receive("正在识别", isFinal: false) == "正在识别")
    }

    @Test("Final results are never replaced by later volatile results")
    func finalizedResults() {
        var state = VoiceInputTranscriptState()
        _ = state.receive("第一段", isFinal: false)
        _ = state.receive("第一段。", isFinal: true)

        #expect(state.receive("第二", isFinal: false) == "第一段。第二")
        #expect(state.receive("第二段。", isFinal: true) == "第一段。第二段。")
    }

    @Test("Reset clears finalized and volatile text")
    func reset() {
        var state = VoiceInputTranscriptState()
        _ = state.receive("已确认", isFinal: true)
        _ = state.receive("未确认", isFinal: false)

        state.reset()

        #expect(state.text.isEmpty)
    }
}

@Suite("Stable live voice transcript")
struct VoiceInputStableTranscriptStateTests {
    @Test("Publishes the first result immediately and appends extensions")
    func immediateAppend() {
        var state = VoiceInputStableTranscriptState()

        #expect(state.receive("我在") == "我在")
        #expect(state.receive("我在往常") == "我在往常")
        #expect(state.receive("我在往常输入") == "我在往常输入")
    }

    @Test("Never rewrites an already published prefix")
    func noLiveRewrite() {
        var state = VoiceInputStableTranscriptState()
        _ = state.receive("这是语音")
        _ = state.receive("这是语音输入")

        #expect(state.receive("那是语音输入") == "这是语音输入")
    }

    @Test("Reset starts a fresh recognition")
    func reset() {
        var state = VoiceInputStableTranscriptState()
        _ = state.receive("first")
        _ = state.receive("first phrase")

        state.reset()

        #expect(state.receive("next") == "next")
        #expect(state.receive("next phrase") == "next phrase")
    }
}

@Suite("Voice transcript correction policy")
struct VoiceTranscriptCorrectionPolicyTests {
    @Test("Accepts a concise corrected transcript")
    func correctedTranscript() {
        #expect(
            VoiceTranscriptCorrectionPolicy.accepted(
                "但是在网上就输入不了了哦",
                replacing: "但是在往常就输不了了哦"
            ) == "但是在网上就输入不了了哦"
        )
    }

    @Test("Keeps the original when correction is empty")
    func emptyCorrection() {
        #expect(
            VoiceTranscriptCorrectionPolicy.accepted("  ", replacing: "xcodebuild")
                == "xcodebuild"
        )
    }

    @Test("Keeps the original when the model adds multiple lines")
    func multilineCorrection() {
        #expect(
            VoiceTranscriptCorrectionPolicy.accepted(
                "Corrected:\nxcodebuild",
                replacing: "xcodebuild"
            ) == "xcodebuild"
        )
    }

    @Test("Keeps the original when the model expands it unexpectedly")
    func expandedCorrection() {
        let explanation = String(repeating: "explanation ", count: 10)

        #expect(
            VoiceTranscriptCorrectionPolicy.accepted(explanation, replacing: "test")
                == "test"
        )
    }
}
