import ClaudeSpyCommon
import Testing

@Suite("Terminal bottom anchor policy")
struct TerminalBottomAnchorPolicyTests {
    @Test("Initial layout starts at the bottom")
    func initialLayoutAnchors() {
        var policy = TerminalBottomAnchorPolicy()

        #expect(policy.targetOffset(currentOffset: 0, maximumOffset: 120) == 120)
    }

    @Test("A bottom viewport follows later layout changes")
    func bottomViewportFollowsLayout() {
        var policy = TerminalBottomAnchorPolicy()
        _ = policy.targetOffset(currentOffset: 0, maximumOffset: 120)

        #expect(policy.targetOffset(currentOffset: 120, maximumOffset: 180) == 180)
    }

    @Test("Manual scrolling is preserved")
    func manualScrollIsPreserved() {
        var policy = TerminalBottomAnchorPolicy()
        _ = policy.targetOffset(currentOffset: 0, maximumOffset: 120)

        #expect(policy.targetOffset(currentOffset: 60, maximumOffset: 180) == nil)
    }

    @Test("Returning to the bottom resumes anchoring")
    func returningToBottomResumesAnchoring() {
        var policy = TerminalBottomAnchorPolicy()
        _ = policy.targetOffset(currentOffset: 0, maximumOffset: 120)
        _ = policy.targetOffset(currentOffset: 60, maximumOffset: 180)

        #expect(policy.targetOffset(currentOffset: 180, maximumOffset: 220) == 220)
    }

    @Test("UIKit clamping to a smaller bottom remains anchored")
    func clampedOffsetRemainsAnchored() {
        var policy = TerminalBottomAnchorPolicy()
        _ = policy.targetOffset(currentOffset: 0, maximumOffset: 180)

        #expect(policy.targetOffset(currentOffset: 120, maximumOffset: 120) == 120)
    }

    @Test("Explicit bottom requests override manual scrolling")
    func forcedAnchorOverridesManualScroll() {
        var policy = TerminalBottomAnchorPolicy()
        _ = policy.targetOffset(currentOffset: 0, maximumOffset: 120)

        #expect(policy.targetOffset(currentOffset: 40, maximumOffset: 180, force: true) == 180)
    }
}
