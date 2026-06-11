import Foundation

/// Audit trail for the 4,096-token budget (Apple TN3193). Every condensation
/// is recorded with tokensBefore/tokensAfter — product invariant #4.
public struct CondensationRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let replacedExchangeRange: ClosedRange<Int>
    public let summaryText: String
    public let tokensBefore: Int
    public let tokensAfter: Int
    /// True when the graceful-degradation path dropped exchanges outright
    /// instead of (or in addition to) summarizing them.
    public let degradedToDrop: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        replacedExchangeRange: ClosedRange<Int>,
        summaryText: String,
        tokensBefore: Int,
        tokensAfter: Int,
        degradedToDrop: Bool,
        createdAt: Date,
    ) {
        self.id = id
        self.sessionID = sessionID
        self.replacedExchangeRange = replacedExchangeRange
        self.summaryText = summaryText
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.degradedToDrop = degradedToDrop
        self.createdAt = createdAt
    }
}
