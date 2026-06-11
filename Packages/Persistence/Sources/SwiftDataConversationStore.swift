import Foundation
import ParloKit
import SwiftData

/// SwiftData persistence for the learning loop. Domain types stay value
/// types; @Model rows live only inside this actor. Scalar columns carry the
/// queryable keys; the full domain value is stored as Codable JSON so the
/// domain model remains the single source of truth.
@Model
final class SDSessionRow {
    @Attribute(.unique) var id: UUID
    var scenarioID: String
    var languageCode: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String

    init(session: ConversationSession) {
        id = session.id
        scenarioID = session.scenarioID
        languageCode = session.language.rawValue
        startedAt = session.startedAt
        endedAt = session.endedAt
        statusRaw = session.status.rawValue
    }
}

@Model
final class SDTurnRow {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var turnIndex: Int
    var payload: Data

    init(id: UUID, sessionID: UUID, turnIndex: Int, payload: Data) {
        self.id = id
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.payload = payload
    }
}

@Model
final class SDCondensationRow {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var createdAt: Date
    var payload: Data

    init(id: UUID, sessionID: UUID, createdAt: Date, payload: Data) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.payload = payload
    }
}

@ModelActor
public actor SwiftDataConversationStore: ConversationStoring {
    /// In-memory store for tests and previews; on-disk is the app default.
    public static func inMemory() throws -> SwiftDataConversationStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SDSessionRow.self, SDTurnRow.self, SDCondensationRow.self,
            configurations: configuration,
        )
        return SwiftDataConversationStore(modelContainer: container)
    }

    public static func onDisk() throws -> SwiftDataConversationStore {
        let container = try ModelContainer(for: SDSessionRow.self, SDTurnRow.self, SDCondensationRow.self)
        return SwiftDataConversationStore(modelContainer: container)
    }

    public func create(session: ConversationSession) async throws {
        if try fetchSessionRow(id: session.id) != nil {
            throw ConversationStoreError.duplicateSession(session.id)
        }
        modelContext.insert(SDSessionRow(session: session))
        try save()
    }

    public func append(turn: Turn) async throws {
        guard try fetchSessionRow(id: turn.sessionID) != nil else {
            throw ConversationStoreError.sessionNotFound(turn.sessionID)
        }
        let payload = try encode(turn)
        modelContext.insert(
            SDTurnRow(id: turn.id, sessionID: turn.sessionID, turnIndex: turn.index, payload: payload),
        )
        try save()
    }

    public func append(condensation: CondensationRecord) async throws {
        guard try fetchSessionRow(id: condensation.sessionID) != nil else {
            throw ConversationStoreError.sessionNotFound(condensation.sessionID)
        }
        let payload = try encode(condensation)
        modelContext.insert(
            SDCondensationRow(
                id: condensation.id,
                sessionID: condensation.sessionID,
                createdAt: condensation.createdAt,
                payload: payload,
            ),
        )
        try save()
    }

    public func finish(sessionID: UUID, endedAt: Date, status: SessionStatus) async throws {
        guard let row = try fetchSessionRow(id: sessionID) else {
            throw ConversationStoreError.sessionNotFound(sessionID)
        }
        row.endedAt = endedAt
        row.statusRaw = status.rawValue
        try save()
    }

    public func fetchSession(id: UUID) async throws -> ConversationSession? {
        guard let row = try fetchSessionRow(id: id) else { return nil }
        return try mapSession(row)
    }

    public func fetchTurns(sessionID: UUID) async throws -> [Turn] {
        let descriptor = FetchDescriptor<SDTurnRow>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.turnIndex)],
        )
        return try modelContext.fetch(descriptor).map { try decode(Turn.self, from: $0.payload) }
    }

    public func fetchCondensationRecords(sessionID: UUID) async throws -> [CondensationRecord] {
        let descriptor = FetchDescriptor<SDCondensationRow>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        return try modelContext.fetch(descriptor).map { try decode(CondensationRecord.self, from: $0.payload) }
    }

    // MARK: - Private

    private func fetchSessionRow(id: UUID) throws -> SDSessionRow? {
        var descriptor = FetchDescriptor<SDSessionRow>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func mapSession(_ row: SDSessionRow) throws -> ConversationSession {
        guard let language = LearningLanguage(rawValue: row.languageCode),
              let status = SessionStatus(rawValue: row.statusRaw)
        else {
            throw ConversationStoreError.storageFailure(detail: "corrupt session row \(row.id)")
        }
        return ConversationSession(
            id: row.id,
            scenarioID: row.scenarioID,
            language: language,
            startedAt: row.startedAt,
            endedAt: row.endedAt,
            status: status,
        )
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw ConversationStoreError.storageFailure(detail: String(describing: error))
        }
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
