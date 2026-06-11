import Foundation

/// A roleplay scenario — the "Dynamic Profile" fed to the on-device model.
public struct Scenario: Sendable, Codable, Equatable, Identifiable {
    public enum Difficulty: String, Sendable, Codable, Equatable {
        case b1
        case b2
    }

    public let id: String
    public let title: String
    public let language: LearningLanguage
    public let personaDescription: String
    public let situationPrompt: String
    public let difficulty: Difficulty
    public let seedVocabulary: [String]
    public let localeNotes: String

    public init(
        id: String,
        title: String,
        language: LearningLanguage,
        personaDescription: String,
        situationPrompt: String,
        difficulty: Difficulty,
        seedVocabulary: [String],
        localeNotes: String,
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.personaDescription = personaDescription
        self.situationPrompt = situationPrompt
        self.difficulty = difficulty
        self.seedVocabulary = seedVocabulary
        self.localeNotes = localeNotes
    }
}
