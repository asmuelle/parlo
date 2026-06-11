@testable import ConversationEngine
import Foundation
import ParloKit

/// Deterministic model double that records every prompt it receives.
actor RecordingModel: LanguageModelProviding {
    private(set) var prompts: [RoleplayPrompt] = []
    private let turn: RoleplayTurn

    init(turn: RoleplayTurn = RecordingModel.defaultTurn) {
        self.turn = turn
    }

    static let defaultTurn = RoleplayTurn(
        reply: "¡Marchando!",
        correction: nil,
        naturalness: Naturalness(score: 0.9, note: "Suena natural."),
    )

    func generateTurn(for prompt: RoleplayPrompt) async throws -> RoleplayTurn {
        prompts.append(prompt)
        return turn
    }

    func receivedPrompts() -> [RoleplayPrompt] {
        prompts
    }
}

/// Fails decoding a configurable number of times, then succeeds.
actor FlakyDecodingModel: LanguageModelProviding {
    private var remainingFailures: Int
    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func generateTurn(for _: RoleplayPrompt) async throws -> RoleplayTurn {
        callCount += 1
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw RoleplayModelError.decodingFailed(detail: "synthetic decode failure")
        }
        return RecordingModel.defaultTurn
    }

    func calls() -> Int {
        callCount
    }
}

struct UnavailableModel: LanguageModelProviding {
    func generateTurn(for _: RoleplayPrompt) async throws -> RoleplayTurn {
        throw RoleplayModelError.modelUnavailable(detail: "no on-device model")
    }
}

/// Summarizer double that always throws, to exercise graceful degradation.
struct ThrowingSummarizer: TranscriptSummarizing {
    struct SummarizerFailure: Error {}

    func summarize(existingSummary _: String?, exchanges _: [HistoryExchange], scenario _: Scenario) async throws -> String {
        throw SummarizerFailure()
    }
}

/// In-memory store double living in the test target so engine tests do not
/// depend on the Persistence module (module-map rule).
actor SpyStore: ConversationStoring {
    private(set) var sessions: [ConversationSession] = []
    private(set) var turns: [Turn] = []
    private(set) var condensations: [CondensationRecord] = []
    var failAppends = false

    func setFailAppends(_ fail: Bool) {
        failAppends = fail
    }

    func create(session: ConversationSession) async throws {
        sessions.append(session)
    }

    func append(turn: Turn) async throws {
        if failAppends { throw ConversationStoreError.storageFailure(detail: "synthetic write failure") }
        turns.append(turn)
    }

    func append(condensation: CondensationRecord) async throws {
        if failAppends { throw ConversationStoreError.storageFailure(detail: "synthetic write failure") }
        condensations.append(condensation)
    }

    func finish(sessionID: UUID, endedAt: Date, status: SessionStatus) async throws {
        sessions = sessions.map { session in
            session.id == sessionID ? session.ended(at: endedAt, status: status) : session
        }
    }

    func fetchSession(id: UUID) async throws -> ConversationSession? {
        sessions.first { $0.id == id }
    }

    func fetchTurns(sessionID: UUID) async throws -> [Turn] {
        turns.filter { $0.sessionID == sessionID }
    }

    func fetchCondensationRecords(sessionID: UUID) async throws -> [CondensationRecord] {
        condensations.filter { $0.sessionID == sessionID }
    }

    func storedTurns() -> [Turn] {
        turns
    }

    func storedCondensations() -> [CondensationRecord] {
        condensations
    }

    func storedSessions() -> [ConversationSession] {
        sessions
    }
}

enum TestData {
    static func transcript(_ text: String, index: Int = 0) -> VerbatimTranscript {
        VerbatimTranscript(text: text, engine: .mock, rawAudioRef: "mock-audio/\(index).caf")
    }

    /// A budget small enough to force condensation quickly in tests.
    static var tinyBudget: TokenBudget {
        guard let budget = TokenBudget(contextWindow: 1024, callBudget: 640, responseReserve: 200) else {
            fatalError("test budget arithmetic is wrong")
        }
        return budget
    }
}
