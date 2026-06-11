@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

@Suite("ScriptedCafeModel — deterministic mock provider")
struct ScriptedCafeModelTests {
    private func prompt(_ utterance: String) -> RoleplayPrompt {
        RoleplayPrompt(scenario: ScenarioCatalog.cafeMadrid, history: .empty, learnerUtterance: utterance)
    }

    @Test
    func `replies follow the script in order and cycle`() async throws {
        // Arrange
        let model = ScriptedCafeModel(script: ["uno", "dos"], rules: [])

        // Act
        let first = try await model.generateTurn(for: prompt("hola"))
        let second = try await model.generateTurn(for: prompt("hola"))
        let third = try await model.generateTurn(for: prompt("hola"))

        // Assert
        #expect(first.reply == "uno")
        #expect(second.reply == "dos")
        #expect(third.reply == "uno")
    }

    @Test
    func `known B1 error patterns produce a matching correction suggestion`() async throws {
        // Arrange
        let model = ScriptedCafeModel()

        // Act
        let turn = try await model.generateTurn(for: prompt("yo quiero un cafe"))

        // Assert: first matching rule wins ("yo quiero" before "quiero")
        let correction = try #require(turn.correction)
        #expect(correction.originalSpan == "yo quiero")
        #expect(correction.correctedSpan == "quisiera")
        #expect(correction.category == .register)
    }

    @Test
    func `clean utterances get no correction and high naturalness`() async throws {
        // Arrange
        let model = ScriptedCafeModel()

        // Act
        let turn = try await model.generateTurn(for: prompt("quisiera un café con leche, por favor"))

        // Assert
        #expect(turn.correction == nil)
        #expect(turn.naturalness.score > 0.8)
    }

    @Test
    func `naturalness drops as more error patterns match, floored above zero`() async throws {
        // Arrange
        let model = ScriptedCafeModel()

        // Act
        let messy = try await model.generateTurn(for: prompt("yo quiero un cafe con el leche"))
        let clean = try await model.generateTurn(for: prompt("quisiera una tostada"))

        // Assert
        #expect(messy.naturalness.score < clean.naturalness.score)
        #expect(messy.naturalness.score >= 0.35)
    }
}
