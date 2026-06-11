import Foundation
import ParloKit
@testable import Persistence
import Testing

/// Behavioral contract both store implementations must satisfy.
enum StoreFixtures {
    static func session() -> ConversationSession {
        ConversationSession(scenarioID: "es.cafe.madrid", language: .spanish, startedAt: Date(timeIntervalSince1970: 1000))
    }

    static func turn(sessionID: UUID, index: Int) -> Turn {
        Turn(
            sessionID: sessionID,
            index: index,
            transcript: VerbatimTranscript(
                text: "quisiera un café (\(index))",
                engine: .mock,
                rawAudioRef: "mock-audio/\(index).caf",
            ),
            reply: "¡Marchando!",
            naturalness: Naturalness(score: 0.85, note: "Suena natural."),
            correction: GatedCorrection(
                suggestion: CorrectionSuggestion(originalSpan: "quiero", correctedSpan: "quisiera", category: .register),
                outcome: index.isMultiple(of: 2) ? .shown : .suppressed(reason: "no-change"),
            ),
            latencyMs: 420,
        )
    }

    static func condensation(sessionID: UUID) -> CondensationRecord {
        CondensationRecord(
            sessionID: sessionID,
            replacedExchangeRange: 0 ... 4,
            summaryText: "pidió un café y una tostada",
            tokensBefore: 900,
            tokensAfter: 300,
            degradedToDrop: false,
            createdAt: Date(timeIntervalSince1970: 2000),
        )
    }
}

/// Runs the shared contract against any ConversationStoring implementation.
func assertStoreContract(makeStore: @Sendable () async throws -> any ConversationStoring) async throws {
    let store = try await makeStore()
    let session = StoreFixtures.session()

    // create + duplicate rejection
    try await store.create(session: session)
    await #expect(throws: ConversationStoreError.duplicateSession(session.id)) {
        try await store.create(session: session)
    }

    // appending to a missing session fails loudly
    let orphan = StoreFixtures.turn(sessionID: UUID(), index: 0)
    await #expect(throws: ConversationStoreError.self) {
        try await store.append(turn: orphan)
    }

    // turns round-trip in index order even when appended out of order
    try await store.append(turn: StoreFixtures.turn(sessionID: session.id, index: 1))
    try await store.append(turn: StoreFixtures.turn(sessionID: session.id, index: 0))
    let turns = try await store.fetchTurns(sessionID: session.id)
    #expect(turns.map(\.index) == [0, 1])
    #expect(turns[0] == StoreFixtures.turn(sessionID: session.id, index: 0)
        .withIdentity(of: turns[0]))

    // condensation audit records round-trip
    try await store.append(condensation: StoreFixtures.condensation(sessionID: session.id))
    let records = try await store.fetchCondensationRecords(sessionID: session.id)
    #expect(records.count == 1)
    #expect(records[0].tokensBefore == 900)
    #expect(records[0].replacedExchangeRange == 0 ... 4)

    // finishing updates status immutably
    try await store.finish(sessionID: session.id, endedAt: Date(timeIntervalSince1970: 3000), status: .completed)
    let fetched = try await store.fetchSession(id: session.id)
    #expect(fetched?.status == .completed)
    #expect(fetched?.endedAt == Date(timeIntervalSince1970: 3000))
}

extension Turn {
    /// Identity-insensitive comparison helper: UUIDs differ per construction.
    func withIdentity(of other: Turn) -> Turn {
        Turn(
            id: other.id,
            sessionID: sessionID,
            index: index,
            transcript: transcript,
            reply: reply,
            naturalness: naturalness,
            correction: correction,
            latencyMs: latencyMs,
        )
    }
}

@Suite("InMemoryConversationStore")
struct InMemoryConversationStoreTests {
    @Test
    func `satisfies the shared store contract`() async throws {
        try await assertStoreContract { InMemoryConversationStore() }
    }

    @Test
    func `sessions are isolated from each other`() async throws {
        // Arrange
        let store = InMemoryConversationStore()
        let one = StoreFixtures.session()
        let two = ConversationSession(scenarioID: "es.cafe.madrid", language: .spanish, startedAt: Date())
        try await store.create(session: one)
        try await store.create(session: two)

        // Act
        try await store.append(turn: StoreFixtures.turn(sessionID: one.id, index: 0))

        // Assert
        #expect(try await store.fetchTurns(sessionID: two.id).isEmpty)
        #expect(try await store.fetchTurns(sessionID: one.id).count == 1)
    }
}

/// Serialized: concurrent in-memory ModelContainer setup/teardown under the
/// parallel Swift Testing runner has produced rare exit-time segfaults;
/// serializing this suite removes the container churn race.
@Suite("SwiftDataConversationStore (in-memory container)", .serialized)
struct SwiftDataConversationStoreTests {
    @Test
    func contract() async throws {
        try await assertStoreContract { try SwiftDataConversationStore.inMemory() }
    }

    @Test
    func `turn payloads survive a full Codable round-trip including gate outcomes`() async throws {
        // Arrange
        let store = try SwiftDataConversationStore.inMemory()
        let session = StoreFixtures.session()
        try await store.create(session: session)
        let original = StoreFixtures.turn(sessionID: session.id, index: 3)

        // Act
        try await store.append(turn: original)
        let fetched = try await store.fetchTurns(sessionID: session.id)

        // Assert
        #expect(fetched.count == 1)
        #expect(fetched[0] == original)
        #expect(fetched[0].correction?.outcome == .suppressed(reason: "no-change"))
        #expect(fetched[0].transcript.rawAudioRef == "mock-audio/3.caf")
    }
}
