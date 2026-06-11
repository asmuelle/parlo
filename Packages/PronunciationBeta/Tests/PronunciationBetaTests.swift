@testable import PronunciationBeta
import Testing

@Suite("PronunciationBeta — invariant #5 anchors")
struct PronunciationBetaTests {
    @Test
    func `beta labeling is mandatory and the label is the literal word Beta`() {
        #expect(PronunciationBeta.isBetaLabelMandatory)
        #expect(PronunciationBeta.betaLabel == "Beta")
    }
}
