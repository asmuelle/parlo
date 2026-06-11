import Foundation
@testable import ParloKit
import Testing

@Suite("Domain models")
struct DomainModelTests {
    @Test
    func `naturalness score is clamped into 0...1`() {
        #expect(Naturalness(score: 1.7, note: "x").score == 1.0)
        #expect(Naturalness(score: -0.3, note: "x").score == 0.0)
        #expect(Naturalness(score: 0.42, note: "x").score == 0.42)
    }

    @Test
    func `naturalness survives a non-finite model value`() {
        #expect(Naturalness(score: .nan, note: "x").score == 0.0)
        #expect(Naturalness(score: .infinity, note: "x").score == 0.0)
    }

    @Test
    func `gated correction isShown reflects the gate outcome only`() {
        // Arrange
        let suggestion = CorrectionSuggestion(
            originalSpan: "quiero",
            correctedSpan: "quisiera",
            category: .register,
        )

        // Act
        let shown = GatedCorrection(suggestion: suggestion, outcome: .shown)
        let suppressed = GatedCorrection(suggestion: suggestion, outcome: .suppressed(reason: "no-change"))

        // Assert
        #expect(shown.isShown)
        #expect(!suppressed.isShown)
    }

    @Test
    func `ended(at:status:) returns a new session and leaves the original untouched`() {
        // Arrange
        let started = Date(timeIntervalSince1970: 1000)
        let session = ConversationSession(scenarioID: "es.cafe.madrid", language: .spanish, startedAt: started)

        // Act
        let finished = session.ended(at: started.addingTimeInterval(60), status: .completed)

        // Assert
        #expect(session.endedAt == nil)
        #expect(session.status == .active)
        #expect(finished.endedAt != nil)
        #expect(finished.status == .completed)
        #expect(finished.id == session.id)
    }

    @Test
    func `turn round-trips through Codable including the condensation-relevant fields`() throws {
        // Arrange
        let turn = Turn(
            sessionID: UUID(),
            index: 3,
            transcript: VerbatimTranscript(text: "quisiera un café", engine: .mock, rawAudioRef: "mock-audio/3.caf"),
            reply: "¡Marchando!",
            naturalness: Naturalness(score: 0.8, note: "Suena natural"),
            correction: nil,
            latencyMs: 412,
        )

        // Act
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(Turn.self, from: data)

        // Assert
        #expect(decoded == turn)
    }
}
