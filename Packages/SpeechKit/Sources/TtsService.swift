import Foundation
import ParloKit

public enum TtsError: Error, Equatable {
    case voiceUnavailable(locale: String)
}

/// Seam for on-device TTS. The real implementation wraps
/// AVSpeechSynthesizer; tests use `RecordingTtsService`.
public protocol TtsService: Sendable {
    func speak(_ text: String, language: LearningLanguage) async throws
}

/// Test/demo double that records what would have been spoken.
public actor RecordingTtsService: TtsService {
    public private(set) var spoken: [(text: String, language: LearningLanguage)] = []

    public init() {}

    public func speak(_ text: String, language: LearningLanguage) async throws {
        spoken.append((text, language))
    }

    public func spokenTexts() -> [String] {
        spoken.map(\.text)
    }
}

#if canImport(AVFoundation)
    import AVFoundation

    /// On-device TTS via AVSpeechSynthesizer. Entirely offline; premium
    /// voices are used automatically where the learner installed them.
    public actor SystemTtsService: TtsService {
        private let synthesizer = AVSpeechSynthesizer()

        public init() {}

        public func speak(_ text: String, language: LearningLanguage) async throws {
            guard let voice = AVSpeechSynthesisVoice(language: language.localeIdentifier) else {
                throw TtsError.voiceUnavailable(locale: language.localeIdentifier)
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            synthesizer.speak(utterance)
        }
    }
#endif
