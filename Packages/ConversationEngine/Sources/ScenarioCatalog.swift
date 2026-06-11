import Foundation
import ParloKit

/// M1 ships exactly one scenario in exactly one language (DESIGN.md M1).
public enum ScenarioCatalog {
    public static let cafeMadrid = Scenario(
        id: "es.cafe.madrid",
        title: "Ordering at a Madrid café",
        language: .spanish,
        personaDescription: "Mateo, a warm and slightly busy waiter at a neighborhood café in Madrid",
        situationPrompt: """
        The learner has just sat down at your café mid-morning. Take their
        order, suggest something from the counter, handle a small follow-up
        request, and settle the bill — all in everyday Madrid Spanish.
        """,
        difficulty: .b1,
        seedVocabulary: ["un café con leche", "una tostada con tomate", "para llevar", "la cuenta, por favor"],
        localeNotes: "In Spain, ordering with \"me pone…\" or \"quisiera…\" sounds natural; \"yo quiero\" is blunt.",
    )

    public static let all: [Scenario] = [cafeMadrid]
}
