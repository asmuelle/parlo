@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

@Suite("TranscriptCondenser — the 4,096 window stays a hard budget")
struct TranscriptCondenserTests {
    private let scenario = ScenarioCatalog.cafeMadrid

    private func longExchange(_ index: Int) -> HistoryExchange {
        HistoryExchange(
            index: index,
            learner: String(repeating: "quisiera un café con leche y una tostada grande ", count: 4) + "(\(index))",
            partner: String(repeating: "marchando ahora mismo se lo preparo enseguida ", count: 4) + "(\(index))",
        )
    }

    private func history(exchangeCount: Int) -> ConversationHistory {
        ConversationHistory(summary: nil, exchanges: (0 ..< exchangeCount).map(longExchange))
    }

    @Test
    func `no condensation when the prompt already fits`() async {
        // Arrange
        let condenser = TranscriptCondenser(budget: .afmDefault)
        let small = history(exchangeCount: 2)

        // Act
        let outcome = await condenser.condenseIfNeeded(
            history: small, scenario: scenario, pendingUtterance: "hola",
            sessionID: UUID(), now: Date(),
        )

        // Assert
        #expect(outcome.record == nil)
        #expect(outcome.history == small)
    }

    @Test
    func `condensation triggers before the budget is exceeded and shrinks tokens`() async throws {
        // Arrange
        let condenser = TranscriptCondenser(budget: TestData.tinyBudget, keepRecentExchanges: 2)
        let big = history(exchangeCount: 8)
        let sessionID = UUID()

        // Act
        let outcome = await condenser.condenseIfNeeded(
            history: big, scenario: scenario, pendingUtterance: "y la cuenta por favor",
            sessionID: sessionID, now: Date(),
        )

        // Assert: audited, shrunk, and the result actually fits the budget
        let record = try #require(outcome.record)
        #expect(record.tokensAfter < record.tokensBefore)
        #expect(record.sessionID == sessionID)
        #expect(record.replacedExchangeRange.lowerBound == 0)
        let tokens = condenser.promptTokens(
            history: outcome.history, scenario: scenario, pendingUtterance: "y la cuenta por favor",
        )
        #expect(TestData.tinyBudget.fits(promptTokens: tokens))

        // The newest exchange survives verbatim; kept exchanges are a suffix
        let kept = outcome.history.exchanges.map(\.index)
        #expect(kept.last == 7)
        #expect(kept == Array((8 - kept.count) ..< 8))
        #expect(record.replacedExchangeRange.upperBound == (kept.first ?? 8) - 1)
        #expect(outcome.history.summary?.isEmpty == false)
    }

    @Test
    func `condensed prompt actually fits the call budget afterwards`() async {
        // Arrange
        let budget = TestData.tinyBudget
        let condenser = TranscriptCondenser(budget: budget, keepRecentExchanges: 2)
        let big = history(exchangeCount: 12)

        // Act
        let outcome = await condenser.condenseIfNeeded(
            history: big, scenario: scenario, pendingUtterance: "gracias",
            sessionID: UUID(), now: Date(),
        )

        // Assert
        let tokens = condenser.promptTokens(
            history: outcome.history, scenario: scenario, pendingUtterance: "gracias",
        )
        #expect(budget.fits(promptTokens: tokens))
    }

    @Test
    func `summarizer failure degrades to dropping oldest exchanges, never throws`() async {
        // Arrange
        let condenser = TranscriptCondenser(
            budget: TestData.tinyBudget,
            summarizer: ThrowingSummarizer(),
            keepRecentExchanges: 2,
        )
        let big = history(exchangeCount: 8)

        // Act
        let outcome = await condenser.condenseIfNeeded(
            history: big, scenario: scenario, pendingUtterance: "gracias",
            sessionID: UUID(), now: Date(),
        )

        // Assert: degraded path is audited and the history shrank
        #expect(outcome.record?.degradedToDrop == true)
        #expect(outcome.history.exchanges.count < big.exchanges.count)
        #expect(outcome.history.exchanges.last?.index == 7)
    }

    @Test
    func `deterministic summarizer caps length and keeps the newest content`() async throws {
        // Arrange: short exchanges so the newest marker survives clipping
        let summarizer = DeterministicSummarizer(maxSummaryCharacters: 200)
        let exchanges = (0 ..< 10).map { index in
            HistoryExchange(index: index, learner: "pedido número \(index)", partner: "marchando \(index)")
        }

        // Act
        let summary = try await summarizer.summarize(
            existingSummary: "ya pidió un café", exchanges: exchanges, scenario: scenario,
        )

        // Assert: capped, and the newest exchange is retained over the oldest
        #expect(summary.count <= 200)
        #expect(summary.contains("pedido número 9"))
        #expect(!summary.contains("pedido número 0 /"))
    }

    @Test
    func `summarizer is deterministic — same input, same output`() async throws {
        let summarizer = DeterministicSummarizer()
        let exchanges = (0 ..< 5).map(longExchange)
        let first = try await summarizer.summarize(existingSummary: nil, exchanges: exchanges, scenario: scenario)
        let second = try await summarizer.summarize(existingSummary: nil, exchanges: exchanges, scenario: scenario)
        #expect(first == second)
    }
}
