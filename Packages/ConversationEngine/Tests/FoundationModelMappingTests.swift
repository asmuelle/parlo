@testable import ConversationEngine
import Foundation
import ParloKit
import Testing

#if canImport(FoundationModels)

    /// The strict mapping from guided-generation output to the domain turn is
    /// pure and testable without ever invoking the live model (invariant #2).
    @Suite("FoundationModelProvider — strict structured mapping")
    struct FoundationModelMappingTests {
        private func raw(
            reply: String = "¡Marchando!",
            original: String? = nil,
            corrected: String? = nil,
            category: String? = nil,
            naturalness: Double = 0.8,
            note: String = "bien",
        ) -> AFMRoleplayTurn {
            AFMRoleplayTurn(
                reply: reply,
                correctionOriginal: original,
                correctionCorrected: corrected,
                correctionCategory: category,
                naturalness: naturalness,
                naturalnessNote: note,
            )
        }

        @Test
        func `complete correction triple maps to a domain suggestion`() throws {
            let turn = try FoundationModelProvider.map(
                raw(original: "quiero", corrected: "quisiera", category: "register"),
            )
            #expect(turn.correction?.originalSpan == "quiero")
            #expect(turn.correction?.category == .register)
        }

        @Test
        func `no correction fields maps to nil correction`() throws {
            let turn = try FoundationModelProvider.map(raw())
            #expect(turn.correction == nil)
        }

        @Test
        func `partial correction fields are a decode failure, not a partial render`() {
            #expect(throws: RoleplayModelError.self) {
                _ = try FoundationModelProvider.map(raw(original: "quiero", corrected: nil, category: "register"))
            }
        }

        @Test
        func `unknown category is a decode failure`() {
            #expect(throws: RoleplayModelError.self) {
                _ = try FoundationModelProvider.map(
                    raw(original: "quiero", corrected: "quisiera", category: "spelling"),
                )
            }
        }

        @Test
        func `category parsing is case-insensitive`() throws {
            let turn = try FoundationModelProvider.map(
                raw(original: "quiero", corrected: "quisiera", category: "Register"),
            )
            #expect(turn.correction?.category == .register)
        }

        @Test
        func `empty reply is a decode failure`() {
            #expect(throws: RoleplayModelError.self) {
                _ = try FoundationModelProvider.map(raw(reply: "   "))
            }
        }

        @Test
        func `out-of-range naturalness is clamped by the domain type`() throws {
            let turn = try FoundationModelProvider.map(raw(naturalness: 7.5))
            #expect(turn.naturalness.score == 1.0)
        }
    }
#endif
