import Foundation
import ParloKit

#if canImport(FoundationModels)
    import FoundationModels

    /// Guided-generation mirror of the domain `RoleplayTurn`. Flat optional
    /// fields keep the schema small for the ~3B model; mapping validates the
    /// combination before anything reaches the engine (invariant #2).
    @Generable
    struct AFMRoleplayTurn {
        @Guide(description: "Your next in-character reply, in the scenario's target language only.")
        var reply: String
        @Guide(description: "Exact words the learner said that could be improved, or omit if none.")
        var correctionOriginal: String?
        @Guide(description: "The improved version of those exact words, or omit if none.")
        var correctionCorrected: String?
        @Guide(description: "One of: grammar, vocab, register. Omit when there is no correction.")
        var correctionCategory: String?
        @Guide(description: "How natural the learner's utterance sounded, from 0.0 to 1.0.")
        var naturalness: Double
        @Guide(description: "One short, friendly sentence about how the utterance sounded.")
        var naturalnessNote: String
    }

    /// Real on-device provider. Never used in unit tests (the deterministic
    /// mock is); compiled everywhere the FoundationModels SDK exists so the
    /// production path cannot rot.
    public struct FoundationModelProvider: LanguageModelProviding {
        private let builder = PromptBuilder()

        public init() {}

        public static var isModelAvailable: Bool {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        }

        public func generateTurn(for prompt: RoleplayPrompt) async throws -> RoleplayTurn {
            guard Self.isModelAvailable else {
                throw RoleplayModelError.modelUnavailable(detail: "on-device model not available on this device")
            }
            let session = LanguageModelSession(instructions: builder.instructions(for: prompt.scenario))
            do {
                let response = try await session.respond(
                    to: builder.render(prompt),
                    generating: AFMRoleplayTurn.self,
                )
                return try Self.map(response.content)
            } catch let error as RoleplayModelError {
                throw error
            } catch {
                throw RoleplayModelError.decodingFailed(detail: String(describing: error))
            }
        }

        /// Strict mapping: a half-present correction is a decode failure, not
        /// a partial render. Throws so the engine can retry or drop the turn.
        static func map(_ raw: AFMRoleplayTurn) throws -> RoleplayTurn {
            let correction: CorrectionSuggestion?
            switch (raw.correctionOriginal, raw.correctionCorrected, raw.correctionCategory) {
            case (nil, nil, nil):
                correction = nil
            case let (.some(original), .some(corrected), .some(categoryRaw)):
                guard let category = CorrectionCategory(rawValue: categoryRaw.lowercased()) else {
                    throw RoleplayModelError.decodingFailed(detail: "unknown correction category: \(categoryRaw)")
                }
                correction = CorrectionSuggestion(
                    originalSpan: original,
                    correctedSpan: corrected,
                    category: category,
                )
            default:
                throw RoleplayModelError.decodingFailed(detail: "partial correction fields in model output")
            }
            guard !raw.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RoleplayModelError.decodingFailed(detail: "empty reply")
            }
            return RoleplayTurn(
                reply: raw.reply,
                correction: correction,
                naturalness: Naturalness(score: raw.naturalness, note: raw.naturalnessNote),
            )
        }
    }
#endif

/// Picks the best available provider: the on-device model when present,
/// otherwise the deterministic scripted mock. The app never crashes for the
/// lack of a model — it tells the truth and keeps working.
public enum RoleplayModelFactory {
    public static func makeDefault() -> any LanguageModelProviding {
        #if canImport(FoundationModels)
            if FoundationModelProvider.isModelAvailable {
                return FoundationModelProvider()
            }
        #endif
        return ScriptedCafeModel()
    }
}
