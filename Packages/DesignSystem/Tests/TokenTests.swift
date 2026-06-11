@testable import DesignSystem
import Testing

@Suite("Design tokens — travel journal direction")
struct TokenTests {
    @Test
    func `paper cream is a light surface (light UI default)`() {
        #expect(ParloPalette.paperCream.luminance > 0.8)
    }

    @Test
    func `espresso ink is dark enough to read on paper cream`() {
        let contrast = (ParloPalette.paperCream.luminance + 0.05) / (ParloPalette.espressoInk.luminance + 0.05)
        // WCAG AA for body text is 4.5:1; we aim well past it.
        #expect(contrast > 7)
    }

    @Test
    func `correction teal is calm — never red-dominant (corrections are not alarms)`() {
        let teal = ParloPalette.correctionTeal
        #expect(teal.green > teal.red)
        #expect(teal.blue > teal.red)
    }

    @Test
    func `color components are clamped to the displayable range`() {
        let token = ColorToken(red: 1.4, green: -0.2, blue: 0.5)
        #expect(token.red == 1.0)
        #expect(token.green == 0.0)
        #expect(token.blue == 0.5)
    }

    @Test
    func `the palette is distinct — no two tokens collapse into one`() {
        let tokens = [
            ParloPalette.paperCream, ParloPalette.cardPaper, ParloPalette.espressoInk,
            ParloPalette.terracotta, ParloPalette.olive, ParloPalette.correctionTeal,
        ]
        for (i, lhs) in tokens.enumerated() {
            for rhs in tokens.dropFirst(i + 1) {
                #expect(lhs != rhs)
            }
        }
    }
}
