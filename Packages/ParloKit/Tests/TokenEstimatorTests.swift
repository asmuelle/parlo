@testable import ParloKit
import Testing

@Suite("TokenEstimator — deterministic, over-counting heuristic")
struct TokenEstimatorTests {
    @Test
    func `empty string costs zero tokens`() {
        // Arrange
        let estimator = TokenEstimator()

        // Act
        let tokens = estimator.tokens(in: "")

        // Assert
        #expect(tokens == 0)
    }

    @Test
    func `ASCII text rounds bytes up at the default 3 bytes per token`() {
        // Arrange
        let estimator = TokenEstimator()

        // Act & Assert: 4 bytes / 3 → ceil = 2
        #expect(estimator.tokens(in: "hola") == 2)
        // 3 bytes / 3 → 1
        #expect(estimator.tokens(in: "una") == 1)
        // 1 byte → 1
        #expect(estimator.tokens(in: "y") == 1)
    }

    @Test
    func `accented Spanish counts UTF-8 bytes, not characters`() {
        // Arrange
        let estimator = TokenEstimator()

        // Act: "café" = 5 UTF-8 bytes (é is 2) → ceil(5/3) = 2
        let tokens = estimator.tokens(in: "café")

        // Assert
        #expect(tokens == 2)
    }

    @Test
    func `estimate over-counts versus a 4-chars-per-token tokenizer`() {
        // Arrange
        let estimator = TokenEstimator()
        let sentence = "quisiera un café con leche y una tostada con tomate por favor"

        // Act
        let estimate = estimator.tokens(in: sentence)
        let optimisticRealTokens = sentence.count / 4

        // Assert: the safety margin must always over-estimate
        #expect(estimate > optimisticRealTokens)
    }

    @Test
    func `array estimation sums the parts`() {
        // Arrange
        let estimator = TokenEstimator()
        let parts = ["hola", "café", ""]

        // Act
        let total = estimator.tokens(in: parts)

        // Assert
        #expect(total == estimator.tokens(in: "hola") + estimator.tokens(in: "café"))
    }

    @Test
    func `bytesPerToken is floored at 1 to avoid division blowups`() {
        // Arrange
        let estimator = TokenEstimator(bytesPerToken: 0)

        // Act & Assert
        #expect(estimator.bytesPerToken == 1)
        #expect(estimator.tokens(in: "abc") == 3)
    }
}
