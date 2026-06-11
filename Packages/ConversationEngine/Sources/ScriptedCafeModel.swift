import Foundation
import ParloKit

/// Deterministic mock model: a Madrid waiter with a fixed script and a small
/// table of B1-typical error patterns. Used by tests and by the app whenever
/// FoundationModels is unavailable (simulator, older devices). Zero network,
/// zero randomness — same inputs, same outputs.
public actor ScriptedCafeModel: LanguageModelProviding {
    public struct CorrectionRule: Sendable {
        public let pattern: String
        public let replacement: String
        public let category: CorrectionCategory

        public init(pattern: String, replacement: String, category: CorrectionCategory) {
            self.pattern = pattern
            self.replacement = replacement
            self.category = category
        }
    }

    public static let defaultScript: [String] = [
        "¡Buenos días! ¿Qué le pongo?",
        "Marchando. ¿Algo de comer con el café?",
        "Tenemos tostadas con tomate y cruasanes recién hechos.",
        "¿Lo quiere para tomar aquí o para llevar?",
        "Muy bien, enseguida se lo preparo.",
        "¿Le pongo algo más mientras espera?",
        "Aquí tiene. ¡Cuidado, que está caliente!",
        "Son dos euros con cincuenta, cuando quiera.",
        "¡Gracias! Que tenga muy buen día.",
    ]

    public static let defaultCorrectionRules: [CorrectionRule] = [
        CorrectionRule(pattern: "yo quiero", replacement: "quisiera", category: .register),
        CorrectionRule(pattern: "quiero", replacement: "quisiera", category: .register),
        CorrectionRule(pattern: "puedo tener", replacement: "me pone", category: .register),
        CorrectionRule(pattern: "el leche", replacement: "la leche", category: .grammar),
        CorrectionRule(pattern: "cafe", replacement: "café", category: .vocab),
        CorrectionRule(pattern: "tostada de tomate", replacement: "tostada con tomate", category: .vocab),
    ]

    private var replyIndex = 0
    private let script: [String]
    private let rules: [CorrectionRule]

    public init(
        script: [String] = ScriptedCafeModel.defaultScript,
        rules: [CorrectionRule] = ScriptedCafeModel.defaultCorrectionRules,
    ) {
        self.script = script.isEmpty ? ScriptedCafeModel.defaultScript : script
        self.rules = rules
    }

    public func generateTurn(for prompt: RoleplayPrompt) async throws -> RoleplayTurn {
        let reply = script[replyIndex % script.count]
        replyIndex += 1

        let utterance = prompt.learnerUtterance.lowercased()
        let matches = rules.filter { utterance.contains($0.pattern) }
        let correction = matches.first.map {
            CorrectionSuggestion(originalSpan: $0.pattern, correctedSpan: $0.replacement, category: $0.category)
        }
        let score = max(0.35, 0.95 - 0.2 * Double(matches.count))
        let note = matches.isEmpty ? "Suena muy natural." : "Casi — un pequeño ajuste y suena perfecto."
        return RoleplayTurn(
            reply: reply,
            correction: correction,
            naturalness: Naturalness(score: score, note: note),
        )
    }
}
