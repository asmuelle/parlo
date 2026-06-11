import Foundation
import ParloKit

public enum AsrError: Error, Equatable {
    case engineUnavailable(detail: String)
    case captureFailed(detail: String)
}

/// Seam for on-device ASR. The M1 real implementation (SpeechTranscriber for
/// es/fr/de with whisper.cpp fallback) plugs in behind this protocol; tests
/// and the simulator demo use `ScriptedAsrService`. Transcripts are always
/// verbatim and always carry a raw-audio reference — pronunciation scoring
/// consumes raw audio, never ASR text (invariant #5).
public protocol AsrService: Sendable {
    var engine: AsrEngine { get }
    func transcribeNextUtterance() async throws -> VerbatimTranscript
}

/// Deterministic learner-side script: B1-typical utterances with deliberate
/// errors that exercise the correction path end to end.
public actor ScriptedAsrService: AsrService {
    public nonisolated let engine: AsrEngine = .mock

    private var index = 0
    private let utterances: [String]

    public init(utterances: [String]) {
        self.utterances = utterances.isEmpty ? Self.spanishCafeLearnerLines : utterances
    }

    public static let spanishCafeLearnerLines: [String] = [
        "hola buenos dias, yo quiero un cafe con leche",
        "puedo tener una tostada tambien",
        "el leche esta muy caliente",
        "para tomar aqui, gracias",
        "la cuenta por favor",
    ]

    public static func spanishCafeLearnerScript() -> ScriptedAsrService {
        ScriptedAsrService(utterances: spanishCafeLearnerLines)
    }

    public func transcribeNextUtterance() async throws -> VerbatimTranscript {
        let text = utterances[index % utterances.count]
        let transcript = VerbatimTranscript(
            text: text,
            engine: engine,
            rawAudioRef: "mock-audio/utterance-\(index).caf",
        )
        index += 1
        return transcript
    }
}
