import ConversationEngine
import Foundation
@testable import Parlo
import ParloKit
import Persistence
import SpeechKit
import Testing

/// App-shell smoke tests: the view model wires engine → gate → UI state
/// correctly, with everything running on deterministic mocks.
@MainActor
@Suite("ConversationViewModel")
struct ConversationViewModelTests {
    private func makeViewModel(
        model: (any LanguageModelProviding)? = nil,
    ) -> (ConversationViewModel, RecordingTtsService) {
        let scenario = ScenarioCatalog.cafeMadrid
        let engine = ConversationEngine(
            scenario: scenario,
            model: model ?? ScriptedCafeModel(),
            store: InMemoryConversationStore(),
        )
        let tts = RecordingTtsService()
        let viewModel = ConversationViewModel(
            scenario: scenario,
            engine: engine,
            asr: ScriptedAsrService.spanishCafeLearnerScript(),
            tts: tts,
        )
        return (viewModel, tts)
    }

    @Test
    func `typed submission produces learner and partner messages and speaks the reply`() async throws {
        // Arrange
        let (viewModel, tts) = makeViewModel()
        await viewModel.startSessionIfNeeded()
        viewModel.draftText = "quiero un cafe por favor"

        // Act
        await viewModel.submitDraft()

        // Assert
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].author == .learner)
        #expect(viewModel.messages[1].author == .partner)
        #expect(viewModel.draftText.isEmpty)
        #expect(await tts.spokenTexts() == [viewModel.messages[1].text])

        // The known error pattern surfaces as a visible, gate-passed chip
        let suggestion = try #require(viewModel.messages[1].visibleCorrection)
        #expect(suggestion.correctedSpan == "quisiera")
    }

    @Test
    func `dismissing a correction hides the chip without touching the gate result`() async throws {
        // Arrange
        let (viewModel, _) = makeViewModel()
        await viewModel.startSessionIfNeeded()
        viewModel.draftText = "quiero un cafe"
        await viewModel.submitDraft()
        let partner = try #require(viewModel.messages.last)
        #expect(partner.visibleCorrection != nil)

        // Act
        viewModel.dismissCorrection(messageID: partner.id)

        // Assert
        let updated = try #require(viewModel.messages.last)
        #expect(updated.visibleCorrection == nil)
        #expect(updated.correction?.isShown == true)
    }

    @Test
    func `gate-suppressed corrections never render (invariant #3 at the UI boundary)`() async throws {
        // Arrange: a model that hallucinates a span the learner never said
        struct HallucinatingModel: LanguageModelProviding {
            func generateTurn(for _: RoleplayPrompt) async throws -> RoleplayTurn {
                RoleplayTurn(
                    reply: "Vale, perfecto.",
                    correction: CorrectionSuggestion(
                        originalSpan: "nunca dije esto",
                        correctedSpan: "otra cosa",
                        category: .vocab,
                    ),
                    naturalness: Naturalness(score: 0.6, note: "bien"),
                )
            }
        }
        let (viewModel, _) = makeViewModel(model: HallucinatingModel())
        await viewModel.startSessionIfNeeded()
        viewModel.draftText = "buenos dias"

        // Act
        await viewModel.submitDraft()

        // Assert: the suggestion exists but is suppressed, so nothing renders
        let partner = try #require(viewModel.messages.last)
        #expect(partner.correction != nil)
        #expect(partner.correction?.isShown == false)
        #expect(partner.visibleCorrection == nil)
    }

    @Test
    func `mic capture pulls the scripted utterance through the ASR seam`() async {
        // Arrange
        let (viewModel, _) = makeViewModel()
        await viewModel.startSessionIfNeeded()

        // Act
        await viewModel.captureUtterance()

        // Assert
        #expect(viewModel.messages.first?.text == ScriptedAsrService.spanishCafeLearnerLines[0])
        #expect(viewModel.messages.count == 2)
    }
}
