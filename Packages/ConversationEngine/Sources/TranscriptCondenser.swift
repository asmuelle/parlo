import Foundation
import ParloKit

/// Seam for summarization. M1 ships a deterministic extractive summarizer;
/// a model-backed summarizer can replace it later behind the same protocol.
public protocol TranscriptSummarizing: Sendable {
    func summarize(
        existingSummary: String?,
        exchanges: [HistoryExchange],
        scenario: Scenario,
    ) async throws -> String
}

/// Deterministic, extractive condensation: keeps the freshest facts, caps
/// length, never calls a model. Cheap, testable, never hallucinates.
public struct DeterministicSummarizer: TranscriptSummarizing {
    public let maxSummaryCharacters: Int

    public init(maxSummaryCharacters: Int = 600) {
        self.maxSummaryCharacters = max(80, maxSummaryCharacters)
    }

    public func summarize(
        existingSummary: String?,
        exchanges: [HistoryExchange],
        scenario _: Scenario,
    ) async throws -> String {
        var parts: [String] = []
        if let existingSummary, !existingSummary.isEmpty {
            parts.append(existingSummary)
        }
        for exchange in exchanges {
            parts.append("L: \(clip(exchange.learner)) / P: \(clip(exchange.partner))")
        }
        let joined = parts.joined(separator: " · ")
        guard joined.count > maxSummaryCharacters else { return joined }
        // Keep the newest content: older facts are the safest to lose.
        return "…" + String(joined.suffix(maxSummaryCharacters - 1))
    }

    private func clip(_ text: String, to limit: Int = 80) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}

public struct CondensationOutcome: Sendable {
    public let history: ConversationHistory
    public let record: CondensationRecord?
}

/// Deterministic pre-call token budgeting (product invariant #4): checked
/// before *every* model invocation; condensation is automatic and audited.
/// Degradation ladder when the summary alone cannot save the budget:
/// summarize oldest → drop oldest remaining → shed the summary. A session
/// never crashes and never silently truncates — every step is recorded.
public struct TranscriptCondenser: Sendable {
    public let budget: TokenBudget
    public let estimator: TokenEstimator
    public let keepRecentExchanges: Int
    private let summarizer: any TranscriptSummarizing
    private let builder = PromptBuilder()

    public init(
        budget: TokenBudget = .afmDefault,
        estimator: TokenEstimator = TokenEstimator(),
        summarizer: any TranscriptSummarizing = DeterministicSummarizer(),
        keepRecentExchanges: Int = 3,
    ) {
        self.budget = budget
        self.estimator = estimator
        self.summarizer = summarizer
        self.keepRecentExchanges = max(1, keepRecentExchanges)
    }

    public func promptTokens(
        history: ConversationHistory,
        scenario: Scenario,
        pendingUtterance: String,
    ) -> Int {
        let prompt = RoleplayPrompt(scenario: scenario, history: history, learnerUtterance: pendingUtterance)
        return estimator.tokens(in: builder.render(prompt))
    }

    /// Never throws: every failure path degrades to a smaller history.
    public func condenseIfNeeded(
        history: ConversationHistory,
        scenario: Scenario,
        pendingUtterance: String,
        sessionID: UUID,
        now: Date,
    ) async -> CondensationOutcome {
        let tokensBefore = promptTokens(history: history, scenario: scenario, pendingUtterance: pendingUtterance)
        guard !budget.fits(promptTokens: tokensBefore) else {
            return CondensationOutcome(history: history, record: nil)
        }

        let reduction = await reduce(history: history, scenario: scenario, pendingUtterance: pendingUtterance)
        let condensed = ConversationHistory(summary: reduction.summary, exchanges: reduction.exchanges)
        guard condensed != history else {
            return CondensationOutcome(history: history, record: nil)
        }

        let tokensAfter = promptTokens(history: condensed, scenario: scenario, pendingUtterance: pendingUtterance)
        let record = CondensationRecord(
            sessionID: sessionID,
            replacedExchangeRange: range(of: reduction.foldedIndices),
            summaryText: reduction.summary ?? "",
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            degradedToDrop: reduction.degraded,
            createdAt: now,
        )
        return CondensationOutcome(history: condensed, record: record)
    }

    // MARK: - Private

    private struct Reduction {
        let summary: String?
        let exchanges: [HistoryExchange]
        let foldedIndices: [Int]
        let degraded: Bool
    }

    /// The degradation ladder: summarize oldest → drop oldest → shed summary.
    private func reduce(
        history: ConversationHistory,
        scenario: Scenario,
        pendingUtterance: String,
    ) async -> Reduction {
        var summary = history.summary
        var exchanges = history.exchanges
        var foldedIndices: [Int] = []
        var degraded = false

        // Step 1: fold the oldest exchanges into the summary.
        if exchanges.count > keepRecentExchanges {
            let folded = Array(exchanges.dropLast(keepRecentExchanges))
            do {
                summary = try await summarizer.summarize(
                    existingSummary: summary, exchanges: folded, scenario: scenario,
                )
                foldedIndices.append(contentsOf: folded.map(\.index))
                exchanges = Array(exchanges.suffix(keepRecentExchanges))
            } catch {
                degraded = true // summarizer failed; fall through to dropping
            }
        }

        // Step 2: drop oldest remaining exchanges until the prompt fits.
        while exchanges.count > 1,
              !fits(summary: summary, exchanges: exchanges, scenario: scenario, pendingUtterance: pendingUtterance)
        {
            let dropped = exchanges.removeFirst()
            foldedIndices.append(dropped.index)
            degraded = true
        }

        // Step 3 (last resort): shed the summary rather than overflow.
        if summary != nil,
           !fits(summary: summary, exchanges: exchanges, scenario: scenario, pendingUtterance: pendingUtterance)
        {
            summary = nil
            degraded = true
        }

        return Reduction(summary: summary, exchanges: exchanges, foldedIndices: foldedIndices, degraded: degraded)
    }

    private func fits(
        summary: String?,
        exchanges: [HistoryExchange],
        scenario: Scenario,
        pendingUtterance: String,
    ) -> Bool {
        let candidate = ConversationHistory(summary: summary, exchanges: exchanges)
        let tokens = promptTokens(history: candidate, scenario: scenario, pendingUtterance: pendingUtterance)
        return budget.fits(promptTokens: tokens)
    }

    private func range(of indices: [Int]) -> ClosedRange<Int> {
        let lower = indices.min() ?? 0
        let upper = indices.max() ?? 0
        return lower ... upper
    }
}
