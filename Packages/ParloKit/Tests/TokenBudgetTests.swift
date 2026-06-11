@testable import ParloKit
import Testing

@Suite("TokenBudget — the hard 4,096 window (invariant #4)")
struct TokenBudgetTests {
    @Test
    func `AFM default matches TN3193 arithmetic`() {
        // Arrange
        let budget = TokenBudget.afmDefault

        // Assert
        #expect(budget.contextWindow == 4096)
        #expect(budget.callBudget == 3200)
        #expect(budget.callBudget + budget.responseReserve <= budget.contextWindow)
    }

    @Test
    func `rejects a budget whose prompt + reserve exceed the window`() {
        // Act
        let budget = TokenBudget(contextWindow: 1000, callBudget: 900, responseReserve: 200)

        // Assert
        #expect(budget == nil)
    }

    @Test
    func `rejects non-positive windows and budgets`() {
        #expect(TokenBudget(contextWindow: 0, callBudget: 1, responseReserve: 0) == nil)
        #expect(TokenBudget(contextWindow: 100, callBudget: 0, responseReserve: 0) == nil)
        #expect(TokenBudget(contextWindow: 100, callBudget: 10, responseReserve: -1) == nil)
    }

    @Test
    func `fits is an inclusive boundary check on the call budget`() throws {
        // Arrange
        let budget = try #require(TokenBudget(contextWindow: 1024, callBudget: 700, responseReserve: 200))

        // Assert
        #expect(budget.fits(promptTokens: 700))
        #expect(!budget.fits(promptTokens: 701))
        #expect(budget.fits(promptTokens: 0))
    }
}
