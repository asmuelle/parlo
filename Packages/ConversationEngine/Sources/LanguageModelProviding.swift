import Foundation
import ParloKit

/// One exchange already completed in this session, as fed back to the model.
public struct HistoryExchange: Sendable, Codable, Equatable {
    public let index: Int
    public let learner: String
    public let partner: String

    public init(index: Int, learner: String, partner: String) {
        self.index = index
        self.learner = learner
        self.partner = partner
    }
}

/// The condensed conversation state that accompanies every model call.
/// Immutable: every change returns a new value.
public struct ConversationHistory: Sendable, Equatable {
    public let summary: String?
    public let exchanges: [HistoryExchange]

    public static let empty = ConversationHistory(summary: nil, exchanges: [])

    public init(summary: String?, exchanges: [HistoryExchange]) {
        self.summary = summary
        self.exchanges = exchanges
    }

    public func appending(_ exchange: HistoryExchange) -> ConversationHistory {
        ConversationHistory(summary: summary, exchanges: exchanges + [exchange])
    }
}

/// Everything the model is allowed to see for one turn.
public struct RoleplayPrompt: Sendable, Equatable {
    public let scenario: Scenario
    public let history: ConversationHistory
    public let learnerUtterance: String

    public init(scenario: Scenario, history: ConversationHistory, learnerUtterance: String) {
        self.scenario = scenario
        self.history = history
        self.learnerUtterance = learnerUtterance
    }
}

public enum RoleplayModelError: Error, Equatable {
    /// Guided generation produced output that does not parse into a
    /// structured turn. Callers retry or drop — never render raw text
    /// (product invariant #2).
    case decodingFailed(detail: String)
    case modelUnavailable(detail: String)
}

/// Seam for the on-device language model. The real implementation wraps
/// FoundationModels guided generation; tests and the simulator demo use the
/// deterministic `ScriptedCafeModel`. No other module may talk to a model.
public protocol LanguageModelProviding: Sendable {
    func generateTurn(for prompt: RoleplayPrompt) async throws -> RoleplayTurn
}
