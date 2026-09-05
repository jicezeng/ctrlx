#if os(macOS)
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Terminal title stabilization")
    struct TerminalTitleStabilizerTests {
        @Test("Braille activity frames collapse to one semantic title")
        func stripsBrailleSpinnerPrefix() {
            for title in ["⠇ coding", "⠏ coding", "⠋ coding", "⠙ coding", "⠸ coding"] {
                #expect(TerminalTitleStabilizer.stabilize(title) == "coding")
            }
        }

        @Test("Only a separated non-empty Braille prefix is transient")
        func preservesMeaningfulTitles() {
            #expect(TerminalTitleStabilizer.stabilize("coding") == "coding")
            #expect(TerminalTitleStabilizer.stabilize("⠇coding") == "⠇coding")
            #expect(TerminalTitleStabilizer.stabilize("⠇  ") == "⠇  ")
            #expect(TerminalTitleStabilizer.stabilize("● coding") == "● coding")
        }

        @Test("Whitespace after the transient glyph is removed")
        func removesSeparatorWhitespace() {
            #expect(TerminalTitleStabilizer.stabilize("⠦  中文会话") == "中文会话")
            #expect(TerminalTitleStabilizer.stabilize("⠦\tbuild") == "build")
        }
    }
#endif
