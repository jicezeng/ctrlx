import ClaudeSpyCommon
import Testing

@Suite("Terminal scrollback policy")
struct TerminalScrollbackPolicyTests {
    @Test("Line limits stay within the shared bounds")
    func normalizesLineLimits() {
        #expect(TerminalScrollbackPolicy.normalizedLineLimit(-1) == 0)
        #expect(TerminalScrollbackPolicy.normalizedLineLimit(10_000) == 10_000)
        #expect(TerminalScrollbackPolicy.normalizedLineLimit(100_000) == 50_000)
    }
}
