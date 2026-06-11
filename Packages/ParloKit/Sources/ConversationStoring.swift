import Foundation

/// Storage seam for the learning loop. Lives in ParloKit so feature modules
/// (ConversationEngine, Persistence) never import each other — they meet
/// here, per the DESIGN.md dependency rule.
public protocol ConversationStoring: Sendable {
    func create(session: ConversationSession) async throws
    func append(turn: Turn) async throws
    func append(condensation: CondensationRecord) async throws
    func finish(sessionID: UUID, endedAt: Date, status: SessionStatus) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchTurns(sessionID: UUID) async throws -> [Turn]
    func fetchCondensationRecords(sessionID: UUID) async throws -> [CondensationRecord]
}

public enum ConversationStoreError: Error, Equatable {
    case sessionNotFound(UUID)
    case duplicateSession(UUID)
    case storageFailure(detail: String)
}
