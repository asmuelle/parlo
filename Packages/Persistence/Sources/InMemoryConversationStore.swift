import Foundation
import ParloKit

/// Reference implementation of `ConversationStoring`. Used by previews and
/// as the behavioral spec the SwiftData store must match.
public actor InMemoryConversationStore: ConversationStoring {
    private var sessions: [UUID: ConversationSession] = [:]
    private var turns: [UUID: [Turn]] = [:]
    private var condensations: [UUID: [CondensationRecord]] = [:]

    public init() {}

    public func create(session: ConversationSession) async throws {
        guard sessions[session.id] == nil else {
            throw ConversationStoreError.duplicateSession(session.id)
        }
        sessions[session.id] = session
    }

    public func append(turn: Turn) async throws {
        guard sessions[turn.sessionID] != nil else {
            throw ConversationStoreError.sessionNotFound(turn.sessionID)
        }
        turns[turn.sessionID, default: []].append(turn)
    }

    public func append(condensation: CondensationRecord) async throws {
        guard sessions[condensation.sessionID] != nil else {
            throw ConversationStoreError.sessionNotFound(condensation.sessionID)
        }
        condensations[condensation.sessionID, default: []].append(condensation)
    }

    public func finish(sessionID: UUID, endedAt: Date, status: SessionStatus) async throws {
        guard let session = sessions[sessionID] else {
            throw ConversationStoreError.sessionNotFound(sessionID)
        }
        sessions[sessionID] = session.ended(at: endedAt, status: status)
    }

    public func fetchSession(id: UUID) async throws -> ConversationSession? {
        sessions[id]
    }

    public func fetchTurns(sessionID: UUID) async throws -> [Turn] {
        (turns[sessionID] ?? []).sorted { $0.index < $1.index }
    }

    public func fetchCondensationRecords(sessionID: UUID) async throws -> [CondensationRecord] {
        (condensations[sessionID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}
