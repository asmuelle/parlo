@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

@Suite("PromptBuilder — deterministic rendering")
struct PromptBuilderTests {
    private let builder = PromptBuilder()
    private let scenario = ScenarioCatalog.cafeMadrid

    @Test
    func `rendering is a pure function — same prompt, same string`() {
        // Arrange
        let prompt = RoleplayPrompt(
            scenario: scenario,
            history: ConversationHistory(
                summary: "ya pidió un café",
                exchanges: [HistoryExchange(index: 0, learner: "hola", partner: "¡buenos días!")],
            ),
            learnerUtterance: "quisiera una tostada",
        )

        // Act & Assert
        #expect(builder.render(prompt) == builder.render(prompt))
    }

    @Test
    func `render includes summary, exchanges, and the new utterance in order`() throws {
        // Arrange
        let prompt = RoleplayPrompt(
            scenario: scenario,
            history: ConversationHistory(
                summary: "el aprendiz ya pidió un café con leche",
                exchanges: [HistoryExchange(index: 3, learner: "y una tostada", partner: "marchando")],
            ),
            learnerUtterance: "la cuenta por favor",
        )

        // Act
        let rendered = builder.render(prompt)

        // Assert: ordering of the sections
        let summaryRange = try #require(rendered.range(of: "ya pidió un café con leche"))
        let exchangeRange = try #require(rendered.range(of: "y una tostada"))
        let utteranceRange = try #require(rendered.range(of: "la cuenta por favor"))
        #expect(summaryRange.lowerBound < exchangeRange.lowerBound)
        #expect(exchangeRange.lowerBound < utteranceRange.lowerBound)
    }

    @Test
    func `empty history renders without summary or exchange lines`() {
        // Arrange
        let prompt = RoleplayPrompt(scenario: scenario, history: .empty, learnerUtterance: "hola")

        // Act
        let rendered = builder.render(prompt)

        // Assert
        #expect(!rendered.contains("Earlier in this conversation"))
        #expect(rendered.contains("Learner: hola"))
    }

    @Test
    func `instructions frame the partner as a friend, in character, in the target language`() {
        // Act
        let instructions = builder.instructions(for: scenario)

        // Assert
        #expect(instructions.contains("Mateo"))
        #expect(instructions.contains("Spanish"))
        #expect(instructions.contains("conversation partner"))
        #expect(instructions.contains(scenario.seedVocabulary[0]))
    }
}
