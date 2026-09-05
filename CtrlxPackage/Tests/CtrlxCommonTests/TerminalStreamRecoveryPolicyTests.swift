import Foundation
import Testing
@testable import CtrlxCommon

@Suite("Terminal stream recovery policy")
struct TerminalStreamRecoveryPolicyTests {
    @Test("The first request does not stop another viewer's stream")
    func initialRequest() {
        var policy = TerminalStreamRecoveryPolicy()

        #expect(policy.nextStartMode() == .initial)
        #expect(policy.hasRequestedStream)
    }

    @Test("Reconnect and retry replace the previous subscription")
    func subsequentRequests() {
        var policy = TerminalStreamRecoveryPolicy()

        let initial = policy.nextStartMode()
        let firstReplacement = policy.nextStartMode()
        let secondReplacement = policy.nextStartMode()
        #expect(initial == .initial)
        #expect(firstReplacement == .replaceExisting)
        #expect(secondReplacement == .replaceExisting)
    }

    @Test("Unexpected stream ends are bounded inside the recovery window")
    func unexpectedEndRecoveryIsBounded() {
        var policy = TerminalStreamRecoveryPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        let disconnected = policy.shouldRetryUnexpectedEnd(isConnected: false, now: now)
        let firstConnected = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let secondConnected = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let thirdConnected = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)

        #expect(!disconnected)
        #expect(firstConnected)
        #expect(secondConnected)
        #expect(!thirdConnected)
        #expect(policy.unexpectedEndRetryDates.count == 2)
    }

    @Test("A stable stream restores the automatic recovery budget")
    func stableStreamRestoresBudget() {
        var policy = TerminalStreamRecoveryPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        let firstRetry = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let secondRetry = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let thirdRetry = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        #expect(firstRetry)
        #expect(secondRetry)
        #expect(!thirdRetry)

        policy.markStreamingStable()

        #expect(policy.unexpectedEndRetryDates.isEmpty)
        let retryAfterStableStream = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        #expect(retryAfterStableStream)
    }

    @Test("An expired recovery window permits an isolated retry")
    func expiredWindowRestoresBudget() {
        var policy = TerminalStreamRecoveryPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        let firstRetry = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let secondRetry = policy.shouldRetryUnexpectedEnd(isConnected: true, now: now)
        let retryAfterExpiry = policy.shouldRetryUnexpectedEnd(
            isConnected: true,
            now: now.addingTimeInterval(TerminalStreamRecoveryPolicy.unexpectedEndWindow)
        )
        #expect(firstRetry)
        #expect(secondRetry)
        #expect(retryAfterExpiry)
    }

    @Test("A successful start without initial state retries once")
    func missingInitialStateRecoveryIsBounded() {
        let first = TerminalStreamRecoveryPolicy.resolveSuccessfulStart(
            hasInitialState: false,
            canRetry: true
        )
        let second = TerminalStreamRecoveryPolicy.resolveSuccessfulStart(
            hasInitialState: false,
            canRetry: false
        )

        #expect(first == .retryReplacement)
        #expect(second == .failMissingInitialState)
        #expect(
            TerminalStreamRecoveryPolicy.resolveSuccessfulStart(
                hasInitialState: true,
                canRetry: true
            ) == .ready
        )
    }
}
