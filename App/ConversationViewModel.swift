import ConversationEngine
import Foundation
import Observation
import ParloKit
import Persistence
import SpeechKit

/// Drives one conversation session. Composition: scenario → engine (with the
/// best available model — on-device AFM or the deterministic script) →
/// SwiftData persistence → TTS. All UI state is derived from engine output;
/// corrections render only when the gate said `shown` (invariant #3).
@MainActor
@Observable
final class ConversationViewModel {
    struct Message: Identifiable, Equatable {
        enum Author: Equatable {
            case learner
            case partner
        }

        let id: UUID
        let author: Author
        let text: String
        let correction: GatedCorrection?
        let naturalness: Naturalness?
        var isCorrectionDismissed: Bool

        /// Invariant #3 at the render boundary: only gate-passed corrections
        /// are ever visible.
        var visibleCorrection: CorrectionSuggestion? {
            guard let correction, correction.isShown, !isCorrectionDismissed else { return nil }
            return correction.suggestion
        }
    }

    let scenario: Scenario

    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    private(set) var statusMessage: String?
    private(set) var audioUnavailable = false
    var draftText = ""

    private let engine: ConversationEngine
    private let asr: any AsrService
    private let tts: any TtsService
    private var sessionStarted = false

    init(
        scenario: Scenario,
        engine: ConversationEngine? = nil,
        asr: (any AsrService)? = nil,
        tts: (any TtsService)? = nil,
    ) {
        self.scenario = scenario
        self.engine = engine ?? Self.makeDefaultEngine(scenario: scenario)
        self.asr = asr ?? ScriptedAsrService.spanishCafeLearnerScript()
        self.tts = tts ?? Self.makeDefaultTts()
    }

    private static func makeDefaultEngine(scenario: Scenario) -> ConversationEngine {
        let store: (any ConversationStoring)?
        do {
            store = try SwiftDataConversationStore.onDisk()
        } catch {
            // The conversation still works; it just is not journaled.
            store = nil
        }
        return ConversationEngine(
            scenario: scenario,
            model: RoleplayModelFactory.makeDefault(),
            store: store,
        )
    }

    private static func makeDefaultTts() -> any TtsService {
        #if canImport(AVFoundation)
            return SystemTtsService()
        #else
            return RecordingTtsService()
        #endif
    }

    func startSessionIfNeeded() async {
        guard !sessionStarted else { return }
        do {
            try await engine.startSession()
            sessionStarted = true
        } catch {
            statusMessage = "Couldn't save this session — practice continues, unjournaled."
        }
    }

    /// Mic path: pulls the next utterance from the ASR seam (scripted on
    /// simulator; SpeechTranscriber once SpeechKit's live engine lands).
    func captureUtterance() async {
        guard !isResponding else { return }
        do {
            let transcript = try await asr.transcribeNextUtterance()
            await submit(transcript: transcript)
        } catch {
            statusMessage = "I couldn't hear that — try again."
        }
    }

    /// Typed path: practice by keyboard. No raw audio exists, so the ref is
    /// explicitly marked as typed.
    func submitDraft() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        draftText = ""
        let transcript = VerbatimTranscript(text: text, engine: .typed, rawAudioRef: "typed://no-audio")
        await submit(transcript: transcript)
    }

    func dismissCorrection(messageID: UUID) {
        messages = messages.map { message in
            guard message.id == messageID else { return message }
            var updated = message
            updated.isCorrectionDismissed = true
            return updated
        }
    }

    func endSession() async {
        guard sessionStarted else { return }
        do {
            try await engine.finishSession()
        } catch {
            statusMessage = "Couldn't journal the session end."
        }
    }

    // MARK: - Private

    private func submit(transcript: VerbatimTranscript) async {
        isResponding = true
        statusMessage = nil
        appendLearnerMessage(transcript.text)

        let outcome = await engine.submit(transcript)
        switch outcome {
        case let .completed(exchange):
            appendPartnerMessage(exchange)
            if !exchange.persisted, sessionStarted {
                statusMessage = "Saved nothing for that turn — storage hiccup."
            }
            await speak(exchange.turn.reply)
        case let .dropped(reason):
            statusMessage = userMessage(for: reason)
        }
        isResponding = false
    }

    private func appendLearnerMessage(_ text: String) {
        messages.append(
            Message(
                id: UUID(),
                author: .learner,
                text: text,
                correction: nil,
                naturalness: nil,
                isCorrectionDismissed: false,
            ),
        )
    }

    private func appendPartnerMessage(_ exchange: CompletedExchange) {
        messages.append(
            Message(
                id: UUID(),
                author: .partner,
                text: exchange.turn.reply,
                correction: exchange.turn.correction,
                naturalness: exchange.turn.naturalness,
                isCorrectionDismissed: false,
            ),
        )
    }

    private func speak(_ text: String) async {
        do {
            try await tts.speak(text, language: scenario.language)
            audioUnavailable = false
        } catch {
            audioUnavailable = true
        }
    }

    private func userMessage(for reason: TurnDropReason) -> String {
        switch reason {
        case .modelOutputUnparseable:
            "Mateo lost his train of thought — say that once more?"
        case .modelUnavailable:
            "The on-device model isn't ready on this device — running in practice-script mode."
        case .promptOverBudget:
            "That was a long one! Try splitting it into shorter sentences."
        }
    }
}
