import Foundation

/// Launch languages only — product invariant #7: es/fr/de, nothing else ships
/// without a golden set passing native-speaker QA.
public enum LearningLanguage: String, Sendable, Codable, Equatable, CaseIterable {
    case spanish = "es"
    case french = "fr"
    case german = "de"

    public var localeIdentifier: String {
        switch self {
        case .spanish: "es-ES"
        case .french: "fr-FR"
        case .german: "de-DE"
        }
    }

    public var displayName: String {
        switch self {
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }
}
