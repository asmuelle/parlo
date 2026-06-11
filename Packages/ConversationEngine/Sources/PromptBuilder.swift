import Foundation
import ParloKit

/// Renders prompts deterministically so token estimation measures exactly
/// what the model would receive. Pure function of its inputs.
public struct PromptBuilder: Sendable, Equatable {
    public init() {}

    /// Session-level instructions: persona, situation, and the honest-framing
    /// rules (invariant #10 — a friend leaning over, never a red pen).
    public func instructions(for scenario: Scenario) -> String {
        let vocabulary = scenario.seedVocabulary.joined(separator: ", ")
        return """
        You are \(scenario.personaDescription).
        Situation: \(scenario.situationPrompt)
        Locale notes: \(scenario.localeNotes)
        Useful phrases the learner may try: \(vocabulary).
        You are a friendly conversation partner, not an authority. Stay in
        character, reply briefly in \(scenario.language.displayName), keep the
        scene moving, and treat any correction as a gentle suggestion between
        friends.
        """
    }

    /// Renders the full per-turn prompt: instructions + condensed summary +
    /// recent exchanges + the new learner utterance.
    public func render(_ prompt: RoleplayPrompt) -> String {
        var sections: [String] = [instructions(for: prompt.scenario)]
        if let summary = prompt.history.summary, !summary.isEmpty {
            sections.append("Earlier in this conversation (condensed): \(summary)")
        }
        for exchange in prompt.history.exchanges {
            sections.append("Learner: \(exchange.learner)")
            sections.append("Partner: \(exchange.partner)")
        }
        sections.append("Learner: \(prompt.learnerUtterance)")
        sections.append("Respond with the next structured turn.")
        return sections.joined(separator: "\n")
    }
}
