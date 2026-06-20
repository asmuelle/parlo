@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

@Suite("ConversationEngine — the M1 turn loop")
struct ConversationEngineTests {
    private let scenario = ScenarioCatalog.cafeMadrid

    private func verboseUtterance(_ index: Int) -> String {
        "quisiera pedir otra cosa más para la mesa número \(index), " +
            String(repeating: "y también un poco más de pan con tomate y aceite ", count: 3)
    }

    @Test
    func `fifteen-turn conversation completes without overflow — M1 acceptance analog`() async throws {
        // Arrange
        let store = SpyStore()
        let engine = ConversationEngine(
            scenario: scenario,
            model: ScriptedCafeModel(),
            store: store,
            configuration: .init(budget: TestData.tinyBudget, keepRecentExchanges: 2),
        )
        try await engine.startSession()

        // Act
        var outcomes: [TurnOutcome] = []
        for index in 0 ..< 15 {
            await outcomes.append(engine.submit(TestData.transcript(verboseUtterance(index), index: index)))
        }

        // Assert: every turn completed, none dropped
        let completed = outcomes.compactMap { outcome -> CompletedExchange? in
            if case let .completed(exchange) = outcome { return exchange }
            return nil
        }
        #expect(completed.count == 15)

        // Raw audio is retained per turn (M1 acceptance)
        #expect(completed.allSatisfy { !$0.turn.transcript.rawAudioRef.isEmpty })

        // Condensation happened and was audited
        let records = await store.storedCondensations()
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.tokensAfter < $0.tokensBefore })

        // All turns persisted in order
        let turns = await store.storedTurns()
        #expect(turns.count == 15)
        #expect(turns.map(\.index) == Array(0 ..< 15))

        // Latency instrumented per turn (invariant #9)
        #expect(completed.allSatisfy { $0.turn.latencyMs >= 0 })
    }

    @Test
    func `deterministic-before-model: every prompt the model sees fits the call budget`() async {
        // Arrange
        let budget = TestData.tinyBudget
        let model = RecordingModel()
        let engine = ConversationEngine(
            scenario: scenario,
            model: model,
            configuration: .init(budget: budget, keepRecentExchanges: 2),
        )
        let condenser = TranscriptCondenser(budget: budget)

        // Act
        for index in 0 ..< 12 {
            _ = await engine.submit(TestData.transcript(verboseUtterance(index), index: index))
        }

        // Assert: re-measure every recorded prompt with the same estimator
        let prompts = await model.receivedPrompts()
        #expect(prompts.count == 12)
        for prompt in prompts {
            let tokens = condenser.promptTokens(
                history: prompt.history,
                scenario: prompt.scenario,
                pendingUtterance: prompt.learnerUtterance,
            )
            #expect(budget.fits(promptTokens: tokens), "prompt with \(tokens) tokens exceeded the budget")
        }
    }

    @Test
    func `decode failure retries once, then succeeds without dropping`() async {
        // Arrange
        let model = FlakyDecodingModel(failuresBeforeSuccess: 1)
        let engine = ConversationEngine(scenario: scenario, model: model)

        // Act
        let outcome = await engine.submit(TestData.transcript("quiero un cafe"))

        // Assert
        guard case .completed = outcome else {
            Issue.record("expected completion after one retry")
            return
        }
        #expect(await model.calls() == 2)
    }

    @Test
    func `persistent decode failure drops the turn — raw text never renders (invariant #2)`() async {
        // Arrange
        let model = FlakyDecodingModel(failuresBeforeSuccess: 5)
        let engine = ConversationEngine(scenario: scenario, model: model)

        // Act
        let outcome = await engine.submit(TestData.transcript("quiero un cafe"))

        // Assert
        guard case let .dropped(reason) = outcome else {
            Issue.record("expected drop")
            return
        }
        #expect(reason == .modelOutputUnparseable(detail: "synthetic decode failure"))
        // 1 attempt + 1 retry, never more
        #expect(await model.calls() == 2)
        // The dropped turn must not enter the history
        #expect(await engine.currentHistory.exchanges.isEmpty)
    }

    @Test
    func `model unavailable surfaces as a drop with a user-mappable reason`() async {
        // Arrange
        let engine = ConversationEngine(scenario: scenario, model: UnavailableModel())

        // Act
        let outcome = await engine.submit(TestData.transcript("hola"))

        // Assert
        #expect(outcome == .dropped(.modelUnavailable(detail: "no on-device model")))
    }

    @Test
    func `an utterance that alone exceeds the budget is refused, never sent to the model`() async {
        // Arrange
        let model = RecordingModel()
        let engine = ConversationEngine(
            scenario: scenario,
            model: model,
            configuration: .init(budget: TestData.tinyBudget),
        )
        let giant = String(repeating: "palabras y más palabras sin fin ", count: 200)

        // Act
        let outcome = await engine.submit(TestData.transcript(giant))

        // Assert
        guard case .dropped(.promptOverBudget) = outcome else {
            Issue.record("expected promptOverBudget drop, got \(outcome)")
            return
        }
        #expect(await model.receivedPrompts().isEmpty)
    }

    @Test
    func `corrections that reach the result passed the gate; failing ones are suppressed with reasons`() async throws {
        // Arrange: scripted model corrects "quiero" -> "quisiera"
        let engine = ConversationEngine(scenario: scenario, model: ScriptedCafeModel())

        // Act
        let outcome = await engine.submit(TestData.transcript("quiero un cafe por favor"))

        // Assert
        guard case let .completed(exchange) = outcome else {
            Issue.record("expected completion")
            return
        }
        let correction = try #require(exchange.turn.correction)
        #expect(correction.isShown)
        #expect(correction.suggestion.correctedSpan == "quisiera")

        // And a hallucination-shaped correction gets suppressed end to end
        let lyingModel = RecordingModel(turn: RoleplayTurn(
            reply: "Vale.",
            correction: CorrectionSuggestion(originalSpan: "nunca lo dije", correctedSpan: "otra cosa", category: .vocab),
            naturalness: Naturalness(score: 0.5, note: "ok"),
        ))
        let engine2 = ConversationEngine(scenario: scenario, model: lyingModel)
        let outcome2 = await engine2.submit(TestData.transcript("buenos dias"))
        guard case let .completed(exchange2) = outcome2 else {
            Issue.record("expected completion")
            return
        }
        let gated = try #require(exchange2.turn.correction)
        #expect(!gated.isShown)
    }

    @Test
    func `storage failure keeps the exchange but reports persisted == false`() async throws {
        // Arrange
        let store = SpyStore()
        await store.setFailAppends(true)
        let engine = ConversationEngine(scenario: scenario, model: ScriptedCafeModel(), store: store)
        try await engine.startSession()

        // Act
        let outcome = await engine.submit(TestData.transcript("hola"))

        // Assert
        guard case let .completed(exchange) = outcome else {
            Issue.record("expected completion")
            return
        }
        #expect(exchange.persisted == false)
        #expect(await store.storedTurns().isEmpty)
    }

    @Test
    func `finishing a session marks it completed in the store`() async throws {
        // Arrange
        let store = SpyStore()
        let engine = ConversationEngine(scenario: scenario, model: ScriptedCafeModel(), store: store)
        try await engine.startSession()

        // Act
        try await engine.finishSession()

        // Assert
        let stored = try #require(await store.fetchSession(id: engine.session.id))
        #expect(stored.status == .completed)
        #expect(stored.endedAt != nil)
    }
}
