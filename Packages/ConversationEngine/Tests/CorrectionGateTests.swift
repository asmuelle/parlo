@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

/// Fixture-driven golden tests for the gate (product invariant #3).
struct GateFixture: Codable, CustomTestStringConvertible {
    let name: String
    let utterance: String
    let original: String
    let corrected: String
    let category: String
    let expected: String

    var testDescription: String {
        name
    }

    static func loadAll() throws -> [GateFixture] {
        let url = try #require(
            Bundle.module.url(forResource: "correction_gate_es", withExtension: "json", subdirectory: "Fixtures"),
        )
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(FixtureFile.self, from: data)
        return file.cases
    }

    struct FixtureFile: Codable {
        let language: String
        let cases: [GateFixture]
    }
}

@Suite("CorrectionGate — Spanish golden fixtures")
struct CorrectionGateFixtureTests {
    @Test(arguments: try GateFixture.loadAll())
    func `golden case behaves as the fixture expects`(_ fixture: GateFixture) throws {
        // Arrange
        let gate = CorrectionGate(language: .spanish)
        let category = try #require(CorrectionCategory(rawValue: fixture.category))
        let suggestion = CorrectionSuggestion(
            originalSpan: fixture.original,
            correctedSpan: fixture.corrected,
            category: category,
        )

        // Act
        let gated = gate.evaluate(suggestion, learnerUtterance: fixture.utterance)

        // Assert
        switch gated.outcome {
        case .shown:
            #expect(fixture.expected == "shown", "expected \(fixture.expected) but gate showed it")
        case let .suppressed(reason):
            #expect(
                fixture.expected == "suppressed:\(reason)",
                "expected \(fixture.expected) but gate suppressed with \(reason)",
            )
        }
    }

    @Test
    func `the fixture seed covers both shown and suppressed outcomes`() throws {
        let fixtures = try GateFixture.loadAll()
        let shown = fixtures.filter { $0.expected == "shown" }
        let suppressed = fixtures.filter { $0.expected.hasPrefix("suppressed:") }
        #expect(shown.count >= 8)
        #expect(suppressed.count >= 8)
        #expect(shown.count + suppressed.count == fixtures.count)
    }
}

@Suite("CorrectionGate — unit behavior")
struct CorrectionGateUnitTests {
    private let gate = CorrectionGate(language: .spanish)

    @Test
    func `suppress-on-doubt: every suppression carries a reason`() {
        // Arrange: a hallucinated span
        let suggestion = CorrectionSuggestion(originalSpan: "nunca dije esto", correctedSpan: "algo", category: .vocab)

        // Act
        let gated = gate.evaluate(suggestion, learnerUtterance: "quiero un cafe")

        // Assert
        guard case let .suppressed(reason) = gated.outcome else {
            Issue.record("expected suppression")
            return
        }
        #expect(!reason.isEmpty)
        #expect(!gated.isShown)
    }

    @Test
    func `normalization keeps accents — café and cafe stay different`() {
        #expect(TargetLanguageHeuristics.normalize("Café!") == "café")
        #expect(TargetLanguageHeuristics.normalize("cafe") != TargetLanguageHeuristics.normalize("café"))
    }

    @Test
    func `normalization strips punctuation and collapses whitespace`() {
        #expect(TargetLanguageHeuristics.normalize("¿Quiero   un café?") == "quiero un café")
        #expect(TargetLanguageHeuristics.normalize("«hola», dijo…") == "hola dijo")
    }

    @Test
    func `german charset accepts umlauts that Spanish rejects`() {
        #expect(TargetLanguageHeuristics.usesAllowedCharset("ich möchte", language: .german))
        #expect(!TargetLanguageHeuristics.usesAllowedCharset("ich möchte", language: .spanish))
        #expect(TargetLanguageHeuristics.usesAllowedCharset("garçon", language: .french))
    }

    @Test
    func `english detector matches whole words only`() {
        // "the" inside "tienes" must not trigger
        #expect(!TargetLanguageHeuristics.containsEnglishFunctionWords("tienes leche"))
        #expect(TargetLanguageHeuristics.containsEnglishFunctionWords("the leche"))
    }
}
