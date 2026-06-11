import Foundation
import ParloKit

/// M0 placeholder for the M2 pronunciation path (Core ML wav2vec2 forced
/// alignment + GOP scoring). Two product rules are anchored now so they
/// cannot drift (invariant #5):
/// 1. Scoring consumes *raw audio* references, never ASR text.
/// 2. All pronunciation feedback is labeled Beta until DESIGN.md says
///    otherwise — no false precision, no parity claims with anyone.
public enum PronunciationBeta {
    public static let isBetaLabelMandatory = true
    public static let betaLabel = "Beta"
}
