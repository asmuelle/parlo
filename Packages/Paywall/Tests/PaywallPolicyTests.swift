@testable import Paywall
import Testing

@Suite("PaywallPolicy — invariant #8 constants")
struct PaywallPolicyTests {
    @Test
    func `hard paywall sits after exactly 3 free conversations`() {
        #expect(PaywallPolicy.freeConversationCap == 3)
    }

    @Test
    func `the daily drill is never gated`() {
        #expect(PaywallPolicy.dailyDrillIsAlwaysFree)
    }
}
