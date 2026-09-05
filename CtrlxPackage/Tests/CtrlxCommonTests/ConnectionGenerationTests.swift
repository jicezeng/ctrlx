import Testing
@testable import CtrlxCommon

@Suite("Connection generation and liveness")
struct ConnectionGenerationTests {
    @Test("Invalidation rejects work captured by an older connection")
    func rejectsOldGeneration() {
        var generation = ConnectionGeneration()
        let old = generation.current

        generation.invalidate()

        #expect(!generation.isCurrent(old))
        #expect(generation.isCurrent(generation.current))
    }

    @Test("One silent keepalive round is tolerated")
    func toleratesOneMiss() {
        var policy = ConnectionLivenessPolicy(missedRoundLimit: 2)

        let firstMiss = policy.missedRound()
        #expect(!firstMiss)
        #expect(policy.consecutiveMissedRounds == 1)
        let secondMiss = policy.missedRound()
        #expect(secondMiss)
    }

    @Test("Any inbound frame resets consecutive misses")
    func inboundFrameResetsMisses() {
        var policy = ConnectionLivenessPolicy(missedRoundLimit: 2)

        let firstMiss = policy.missedRound()
        #expect(!firstMiss)
        policy.receivedInboundFrame()

        #expect(policy.consecutiveMissedRounds == 0)
        let missAfterInboundFrame = policy.missedRound()
        #expect(!missAfterInboundFrame)
    }
}
