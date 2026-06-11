import Foundation
import ParloKit

public enum TurnDropReason: Error, Sendable, Equatable {
    /// Guided generation failed to parse after a retry — the turn is dropped,
    /// raw model text is never rendered (invariant #2).
    case modelOutputUnparseable(detail: String)
    case modelUnavailable(detail: String)
    /// The utterance alone exceeds the call budget even after condensation.
    /// Refusing loudly beats overflowing the context window (invariant #4).
    case promptOverBudget(tokens: Int)
}

public struct CompletedExchange: Sendable, Equatable {
    public let turn: Turn
    public let condensation: CondensationRecord?
    /// False when the turn was produced but persisting it failed; the UI
    /// still shows the exchange and surfaces a storage warning.
    public let persisted: Bool
}

public enum TurnOutcome: Sendable, Equatable {
    case completed(CompletedExchange)
    case dropped(TurnDropReason)
}

/// The core M1 loop: deterministic budget check → condensation → structured
/// model turn → correction gate → persistence. One actor per session.
public actor ConversationEngine {
    public struct Configuration: Sendable {
        public let budget: TokenBudget
        public let decodeRetries: Int
        public let keepRecentExchanges: Int

        public init(
            budget: TokenBudget = .afmDefault,
            decodeRetries: Int = 1,
            keepRecentExchanges: Int = 3,
        ) {
            self.budget = budget
            self.decodeRetries = max(0, decodeRetries)
            self.keepRecentExchanges = max(1, keepRecentExchanges)
        }
    }

    public let scenario: Scenario
    public let session: ConversationSession

    private let model: any LanguageModelProviding
    private let store: (any ConversationStoring)?
    private let gate: CorrectionGate
    private let condenser: TranscriptCondenser
    private let configuration: Configuration
    private let clock = ContinuousClock()

    private var history: ConversationHistory = .empty
    private var exchangeCount = 0

    public init(
        scenario: Scenario,
        model: any LanguageModelProviding,
        store: (any ConversationStoring)? = nil,
        configuration: Configuration = Configuration(),
        summarizer: any TranscriptSummarizing = DeterministicSummarizer(),
        startedAt: Date = Date(),
    ) {
        self.scenario = scenario
        self.model = model
        self.store = store
        self.configuration = configuration
        gate = CorrectionGate(language: scenario.language)
        condenser = TranscriptCondenser(
            budget: configuration.budget,
            summarizer: summarizer,
            keepRecentExchanges: configuration.keepRecentExchanges,
        )
        session = ConversationSession(
            scenarioID: scenario.id,
            language: scenario.language,
            startedAt: startedAt,
        )
    }

    /// Registers the session with the store. Throwing here is a hard failure
    /// the caller must surface — a session that cannot persist must say so.
    public func startSession() async throws {
        try await store?.create(session: session)
    }

    public func submit(_ transcript: VerbatimTranscript) async -> TurnOutcome {
        let start = clock.now
        let condensation = await condenseAndAudit(pendingUtterance: transcript.text)

        let promptTokens = condenser.promptTokens(
            history: history, scenario: scenario, pendingUtterance: transcript.text,
        )
        guard configuration.budget.fits(promptTokens: promptTokens) else {
            return .dropped(.promptOverBudget(tokens: promptTokens))
        }

        let prompt = RoleplayPrompt(scenario: scenario, history: history, learnerUtterance: transcript.text)
        let roleplayTurn: RoleplayTurn
        switch await generateWithRetry(prompt: prompt) {
        case let .success(turn): roleplayTurn = turn
        case let .failure(reason): return .dropped(reason)
        }

        let turn = makeTurn(transcript: transcript, roleplayTurn: roleplayTurn, start: start)
        history = history.appending(
            HistoryExchange(index: exchangeCount, learner: transcript.text, partner: roleplayTurn.reply),
        )
        exchangeCount += 1

        let persisted = await persistTurn(turn)
        return .completed(
            CompletedExchange(turn: turn, condensation: condensation, persisted: persisted),
        )
    }

    public func finishSession(status: SessionStatus = .completed) async throws {
        try await store?.finish(sessionID: session.id, endedAt: Date(), status: status)
    }

    public var currentHistory: ConversationHistory {
        history
    }

    // MARK: - Private

    /// Runs deterministic condensation, persists the audit record, and
    /// adopts the (possibly reduced) history.
    private func condenseAndAudit(pendingUtterance: String) async -> CondensationRecord? {
        let outcome = await condenser.condenseIfNeeded(
            history: history,
            scenario: scenario,
            pendingUtterance: pendingUtterance,
            sessionID: session.id,
            now: Date(),
        )
        history = outcome.history
        if let record = outcome.record {
            await persistCondensation(record)
        }
        return outcome.record
    }

    /// Gates the correction and assembles the persisted turn value,
    /// including the per-turn latency instrumentation (invariant #9).
    private func makeTurn(
        transcript: VerbatimTranscript,
        roleplayTurn: RoleplayTurn,
        start: ContinuousClock.Instant,
    ) -> Turn {
        let gated = roleplayTurn.correction.map { gate.evaluate($0, learnerUtterance: transcript.text) }
        let elapsed = clock.now - start
        return Turn(
            sessionID: session.id,
            index: exchangeCount,
            transcript: transcript,
            reply: roleplayTurn.reply,
            naturalness: roleplayTurn.naturalness,
            correction: gated,
            latencyMs: Int(elapsed.components.seconds * 1000) +
                Int(elapsed.components.attoseconds / 1_000_000_000_000_000),
        )
    }

    private func generateWithRetry(prompt: RoleplayPrompt) async -> Result<RoleplayTurn, TurnDropReason> {
        var attempts = 0
        while true {
            do {
                let turn = try await model.generateTurn(for: prompt)
                return .success(turn)
            } catch let RoleplayModelError.decodingFailed(detail) {
                attempts += 1
                if attempts > configuration.decodeRetries {
                    return .failure(.modelOutputUnparseable(detail: detail))
                }
            } catch let RoleplayModelError.modelUnavailable(detail) {
                return .failure(.modelUnavailable(detail: detail))
            } catch {
                return .failure(.modelOutputUnparseable(detail: String(describing: error)))
            }
        }
    }

    private func persistTurn(_ turn: Turn) async -> Bool {
        guard let store else { return false }
        do {
            try await store.append(turn: turn)
            return true
        } catch {
            // The exchange already happened; losing the UI over a storage
            // hiccup would be worse. The caller sees `persisted == false`.
            return false
        }
    }

    private func persistCondensation(_ record: CondensationRecord) async {
        guard let store else { return }
        do {
            try await store.append(condensation: record)
        } catch {
            // Audit-trail write failed; the condensation itself succeeded.
            // Surfaced via CompletedExchange.persisted on the turn write path.
        }
    }
}
