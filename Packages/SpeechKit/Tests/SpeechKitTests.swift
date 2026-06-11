import Foundation
import ParloKit
@testable import SpeechKit
import Testing

@Suite("ScriptedAsrService — deterministic learner script")
struct ScriptedAsrServiceTests {
    @Test
    func `utterances cycle in order with unique raw-audio references`() async throws {
        // Arrange
        let asr = ScriptedAsrService(utterances: ["uno", "dos"])

        // Act
        let first = try await asr.transcribeNextUtterance()
        let second = try await asr.transcribeNextUtterance()
        let third = try await asr.transcribeNextUtterance()

        // Assert
        #expect(first.text == "uno")
        #expect(second.text == "dos")
        #expect(third.text == "uno")
        #expect(first.rawAudioRef != second.rawAudioRef)
        #expect(first.engine == .mock)
    }

    @Test
    func `every transcript retains a raw-audio reference (invariant #5 precondition)`() async throws {
        // Arrange
        let asr = ScriptedAsrService.spanishCafeLearnerScript()

        // Act & Assert
        for _ in 0 ..< 6 {
            let transcript = try await asr.transcribeNextUtterance()
            #expect(!transcript.rawAudioRef.isEmpty)
        }
    }

    @Test
    func `default Spanish script contains the seeded B1 error patterns`() {
        let joined = ScriptedAsrService.spanishCafeLearnerLines.joined(separator: " ")
        #expect(joined.contains("yo quiero"))
        #expect(joined.contains("el leche"))
        #expect(joined.contains("puedo tener"))
    }
}

@Suite("RecordingTtsService")
struct RecordingTtsServiceTests {
    @Test
    func `records spoken text and language in order`() async throws {
        // Arrange
        let tts = RecordingTtsService()

        // Act
        try await tts.speak("¡Buenos días!", language: .spanish)
        try await tts.speak("Marchando.", language: .spanish)

        // Assert
        #expect(await tts.spokenTexts() == ["¡Buenos días!", "Marchando."])
        #expect(await tts.spoken.first?.language == .spanish)
    }
}
