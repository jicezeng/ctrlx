import CtrlxCommon
import Testing

@Suite("Terminal bottom anchor policy")
struct TerminalBottomAnchorPolicyTests {
    @Test("Initial layout starts at the bottom")
    func initialLayoutAnchors() {
        let policy = TerminalBottomAnchorPolicy()

        #expect(policy.targetOffset(maximumOffset: 120) == 120)
    }

    @Test("Automatic intermediate offsets cannot break startup anchoring")
    func intermediateLayoutOffsetsKeepFollowing() {
        let policy = TerminalBottomAnchorPolicy()

        #expect(policy.targetOffset(maximumOffset: 120) == 120)
        // UIKit may temporarily place the viewport between its old and new
        // bottom while safe-area and representable layouts settle. The policy
        // no longer infers user intent from that transient offset.
        #expect(policy.targetOffset(maximumOffset: 180) == 180)
    }

    @Test("Manual scrolling is preserved")
    func manualScrollIsPreserved() {
        var policy = TerminalBottomAnchorPolicy()
        policy.userWillBeginScrolling()
        policy.userDidEndScrolling(currentOffset: 60, maximumOffset: 180)

        #expect(policy.targetOffset(maximumOffset: 220) == nil)
    }

    @Test("Returning to the bottom resumes anchoring")
    func returningToBottomResumesAnchoring() {
        var policy = TerminalBottomAnchorPolicy()
        policy.userWillBeginScrolling()
        policy.userDidEndScrolling(currentOffset: 180, maximumOffset: 180)

        #expect(policy.targetOffset(maximumOffset: 220) == 220)
    }

    @Test("A drag pauses anchoring until it finishes")
    func activeDragPausesAnchoring() {
        var policy = TerminalBottomAnchorPolicy()
        policy.userWillBeginScrolling()

        #expect(policy.targetOffset(maximumOffset: 180) == nil)
    }

    @Test("Explicit bottom requests override manual scrolling")
    func forcedAnchorOverridesManualScroll() {
        var policy = TerminalBottomAnchorPolicy()
        policy.userWillBeginScrolling()
        policy.userDidEndScrolling(currentOffset: 40, maximumOffset: 180)
        policy.requestScrollToBottom()

        #expect(policy.targetOffset(maximumOffset: 180) == 180)
    }

    @Test("Inset-adjusted negative bottom offsets are preserved")
    func negativeBottomOffsetIsPreserved() {
        let policy = TerminalBottomAnchorPolicy()

        #expect(policy.targetOffset(maximumOffset: -12) == -12)
    }
}
