import Foundation
import ParloKit

/// Deterministic validation between the model and the screen (product
/// invariant #3). A correction is shown only if every check passes;
/// suppress-on-doubt is correct behavior — a wrong correction shown is a
/// release blocker. Suppressions carry a machine-readable reason for audit.
public struct CorrectionGate: Sendable {
    public enum SuppressReason {
        public static let emptyCorrection = "empty-correction"
        public static let originalNotInUtterance = "original-span-not-in-utterance"
        public static let noChange = "no-change"
        public static let nonTargetCharset = "non-target-charset"
        public static let englishContent = "english-content"
        public static let lengthImplausible = "length-implausible"
        public static let categoryMismatch = "category-accent-only-not-register"
    }

    public let language: LearningLanguage

    public init(language: LearningLanguage) {
        self.language = language
    }

    public func evaluate(_ suggestion: CorrectionSuggestion, learnerUtterance: String) -> GatedCorrection {
        if let reason = suppressionReason(for: suggestion, learnerUtterance: learnerUtterance) {
            return GatedCorrection(suggestion: suggestion, outcome: .suppressed(reason: reason))
        }
        return GatedCorrection(suggestion: suggestion, outcome: .shown)
    }

    // MARK: - Checks (ordered; first failure wins)

    private func suppressionReason(for suggestion: CorrectionSuggestion, learnerUtterance: String) -> String? {
        let original = TargetLanguageHeuristics.normalize(suggestion.originalSpan)
        let corrected = TargetLanguageHeuristics.normalize(suggestion.correctedSpan)
        let utterance = TargetLanguageHeuristics.normalize(learnerUtterance)

        if corrected.isEmpty {
            return SuppressReason.emptyCorrection
        }
        if original.isEmpty || !utterance.contains(original) {
            return SuppressReason.originalNotInUtterance
        }
        if corrected == original {
            return SuppressReason.noChange
        }
        if !TargetLanguageHeuristics.usesAllowedCharset(corrected, language: language) {
            return SuppressReason.nonTargetCharset
        }
        if TargetLanguageHeuristics.containsEnglishFunctionWords(corrected) {
            return SuppressReason.englishContent
        }
        if corrected.count > 4 * original.count + 24 {
            return SuppressReason.lengthImplausible
        }
        if suggestion.category == .register,
           TargetLanguageHeuristics.foldDiacritics(corrected) == TargetLanguageHeuristics.foldDiacritics(original)
        {
            // An accent-only change is orthography, never a register shift —
            // a model that claims so is confused; do not teach it.
            return SuppressReason.categoryMismatch
        }
        return nil
    }
}

/// Deterministic, language-aware text heuristics used by the gate.
enum TargetLanguageHeuristics {
    private static let punctuation = CharacterSet(charactersIn: "¿¡!?.,;:()[]\"'«»„“”…")

    private static let allowedLetters: [LearningLanguage: Set<Character>] = [
        .spanish: Set("abcdefghijklmnopqrstuvwxyzáéíóúüñ"),
        .french: Set("abcdefghijklmnopqrstuvwxyzàâæçéèêëîïôœùûüÿ"),
        .german: Set("abcdefghijklmnopqrstuvwxyzäöüß"),
    ]

    /// Words that are common in English and not words in es/fr/de. Their
    /// presence in a "target-language" correction means the model drifted.
    private static let englishFunctionWords: Set<String> = [
        "i", "the", "you", "your", "would", "should", "could", "like",
        "please", "want", "is", "are", "this", "that", "with", "have",
    ]

    /// Lowercase, strip punctuation, collapse whitespace. Accents are kept —
    /// they carry meaning in every launch language.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let stripped = String(String.UnicodeScalarView(lowered.unicodeScalars.filter { !punctuation.contains($0) }))
        return stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func foldDiacritics(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    static func usesAllowedCharset(_ normalizedText: String, language: LearningLanguage) -> Bool {
        guard let allowed = allowedLetters[language] else { return false }
        for character in normalizedText where character.isLetter {
            if !allowed.contains(character) { return false }
        }
        return true
    }

    static func containsEnglishFunctionWords(_ normalizedText: String) -> Bool {
        let tokens = normalizedText.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return tokens.contains { englishFunctionWords.contains($0) }
    }
}
