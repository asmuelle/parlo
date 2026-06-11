import ConversationEngine
import DesignSystem
import ParloKit
import SwiftUI

/// Scenario picker styled as a travel journal: cream paper, serif titles,
/// a stamp motif per scenario card. M1 ships exactly one scenario.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ParloPalette.paperCream.color.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: ParloSpacing.lg) {
                        header
                        ForEach(ScenarioCatalog.all) { scenario in
                            NavigationLink(value: scenario.id) {
                                ScenarioCard(scenario: scenario)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(ParloSpacing.md)
                }
            }
            .navigationDestination(for: String.self) { scenarioID in
                if let scenario = ScenarioCatalog.all.first(where: { $0.id == scenarioID }) {
                    ConversationView(viewModel: ConversationViewModel(scenario: scenario))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ParloSpacing.xs) {
            Text("Parlo")
                .font(ParloTypography.journalHeading)
                .foregroundStyle(ParloPalette.espressoInk.color)
            Text("Your conversation fluency partner — entirely on this device.")
                .font(ParloTypography.caption)
                .foregroundStyle(ParloPalette.olive.color)
        }
        .padding(.top, ParloSpacing.lg)
    }
}

struct ScenarioCard: View {
    let scenario: Scenario

    var body: some View {
        VStack(alignment: .leading, spacing: ParloSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: ParloSpacing.xs) {
                    Text(scenario.language.displayName.uppercased())
                        .font(ParloTypography.caption)
                        .kerning(1.2)
                        .foregroundStyle(ParloPalette.terracotta.color)
                    Text(scenario.title)
                        .font(ParloTypography.scenarioTitle)
                        .foregroundStyle(ParloPalette.espressoInk.color)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundStyle(ParloPalette.olive.color)
                    .padding(ParloSpacing.sm)
                    .background(
                        Circle().strokeBorder(
                            ParloPalette.olive.color.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]),
                        ),
                    )
            }
            Text(scenario.seedVocabulary.joined(separator: "  ·  "))
                .font(ParloTypography.caption)
                .foregroundStyle(ParloPalette.espressoInk.color.opacity(0.65))
                .lineLimit(2)
        }
        .padding(ParloSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ParloRadius.card)
                .fill(ParloPalette.cardPaper.color)
                .shadow(color: ParloPalette.espressoInk.color.opacity(0.08), radius: 3, y: 2),
        )
    }
}

#Preview {
    RootView()
}
