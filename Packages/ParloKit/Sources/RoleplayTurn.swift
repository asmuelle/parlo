import Foundation

/// Product invariant #2: conversation output is only ever a parsed, structured
/// `RoleplayTurn`. Raw model text never reaches the UI.
public struct RoleplayTurn: Sendable, Codable, Equatable {
    public let reply: String
    public let correction: CorrectionSuggestion?
    public let naturalness: Naturalness

    public init(reply: String, correction: CorrectionSuggestion?, naturalness: Naturalness) {
        self.reply = reply
        self.correction = correction
        self.naturalness = naturalness
    }
}

/// A naturalness assessment of the learner's utterance. Score is always
/// clamped to 0...1 so a malformed model value can never break the meter.
public struct Naturalness: Sendable, Codable, Equatable {
    public let score: Double
    public let note: String

    public init(score: Double, note: String) {
        self.score = score.isFinite ? min(max(score, 0), 1) : 0
        self.note = note
    }
}

public enum CorrectionCategory: String, Sendable, Codable, Equatable, CaseIterable {
    case grammar
    case vocab
    case register
}

/// A candidate correction proposed by the model. It is a *suggestion* until
/// `CorrectionGate` decides it may be shown (product invariant #3).
public struct CorrectionSuggestion: Sendable, Codable, Equatable {
    public let originalSpan: String
    public let correctedSpan: String
    public let category: CorrectionCategory

    public init(originalSpan: String, correctedSpan: String, category: CorrectionCategory) {
        self.originalSpan = originalSpan
        self.correctedSpan = correctedSpan
        self.category = category
    }
}

/// The result of gating a correction. Suppress-on-doubt is correct behavior;
/// a wrong correction shown is a release blocker.
public enum GateOutcome: Sendable, Codable, Equatable {
    case shown
    case suppressed(reason: String)
}

public struct GatedCorrection: Sendable, Codable, Equatable {
    public let suggestion: CorrectionSuggestion
    public let outcome: GateOutcome

    public init(suggestion: CorrectionSuggestion, outcome: GateOutcome) {
        self.suggestion = suggestion
        self.outcome = outcome
    }

    public var isShown: Bool {
        outcome == .shown
    }
}
