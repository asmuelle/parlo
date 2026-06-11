import Foundation

public enum TurnRole: String, Sendable, Codable, Equatable {
    case learner
    case partner
}

public enum AsrEngine: String, Sendable, Codable, Equatable {
    case speechTranscriber
    case whisper
    case typed
    case mock
}

public enum SessionStatus: String, Sendable, Codable, Equatable {
    case active
    case completed
    case abandoned
}

public struct ConversationSession: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let scenarioID: String
    public let language: LearningLanguage
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus

    public init(
        id: UUID = UUID(),
        scenarioID: String,
        language: LearningLanguage,
        startedAt: Date,
        endedAt: Date? = nil,
        status: SessionStatus = .active,
    ) {
        self.id = id
        self.scenarioID = scenarioID
        self.language = language
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }

    /// Immutable update — returns a finished copy, never mutates in place.
    public func ended(at endedAt: Date, status: SessionStatus) -> ConversationSession {
        ConversationSession(
            id: id,
            scenarioID: scenarioID,
            language: language,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
        )
    }
}

/// A verbatim ASR transcript. `rawAudioRef` is the opaque reference to the
/// retained raw audio buffer — pronunciation scoring consumes raw audio,
/// never ASR text (product invariant #5).
public struct VerbatimTranscript: Sendable, Codable, Equatable {
    public let text: String
    public let engine: AsrEngine
    public let rawAudioRef: String

    public init(text: String, engine: AsrEngine, rawAudioRef: String) {
        self.text = text
        self.engine = engine
        self.rawAudioRef = rawAudioRef
    }
}

/// One completed exchange: learner utterance plus the gated partner response.
public struct Turn: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let index: Int
    public let transcript: VerbatimTranscript
    public let reply: String
    public let naturalness: Naturalness
    public let correction: GatedCorrection?
    public let latencyMs: Int

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        index: Int,
        transcript: VerbatimTranscript,
        reply: String,
        naturalness: Naturalness,
        correction: GatedCorrection?,
        latencyMs: Int,
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.transcript = transcript
        self.reply = reply
        self.naturalness = naturalness
        self.correction = correction
        self.latencyMs = latencyMs
    }
}
