import DesignSystem
import ParloKit
import SwiftUI

/// The chat surface: journal-paper background, rounded bubbles that settle
/// with a gentle spring, teal correction chips (a friend leaning over — never
/// a red pen), and an ink-fill naturalness meter.
struct ConversationView: View {
    @State var viewModel: ConversationViewModel

    var body: some View {
        ZStack {
            ParloPalette.paperCream.color.ignoresSafeArea()
            VStack(spacing: 0) {
                messageList
                if let status = viewModel.statusMessage {
                    statusBanner(status)
                }
                inputBar
            }
        }
        .navigationTitle(viewModel.scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.startSessionIfNeeded() }
        .onDisappear {
            Task { await viewModel.endSession() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ParloSpacing.sm) {
                    sceneIntro
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message) {
                            viewModel.dismissCorrection(messageID: message.id)
                        }
                        .id(message.id)
                    }
                }
                .padding(ParloSpacing.md)
            }
            .onChange(of: viewModel.messages.count) {
                guard let last = viewModel.messages.last else { return }
                withAnimation(.spring(
                    response: ParloMotion.bubbleSpringResponse,
                    dampingFraction: ParloMotion.bubbleSpringDamping,
                )) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var sceneIntro: some View {
        VStack(spacing: ParloSpacing.xs) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(ParloPalette.olive.color)
            Text(viewModel.scenario.situationPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(ParloTypography.caption)
                .foregroundStyle(ParloPalette.espressoInk.color.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, ParloSpacing.md)
    }

    private func statusBanner(_ status: String) -> some View {
        Text(status)
            .font(ParloTypography.caption)
            .foregroundStyle(ParloPalette.espressoInk.color.opacity(0.7))
            .padding(.horizontal, ParloSpacing.md)
            .padding(.vertical, ParloSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(ParloPalette.cardPaper.color)
    }

    private var inputBar: some View {
        HStack(spacing: ParloSpacing.sm) {
            TextField("Escribe en español…", text: $viewModel.draftText)
                .font(ParloTypography.bubble)
                .textFieldStyle(.plain)
                .padding(.horizontal, ParloSpacing.md)
                .padding(.vertical, ParloSpacing.sm)
                .background(
                    Capsule().fill(.white.opacity(0.8)),
                )
                .onSubmit { Task { await viewModel.submitDraft() } }

            Button {
                Task { await viewModel.submitDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(viewModel.isResponding || viewModel.draftText.isEmpty)
            .accessibilityLabel("Send")

            Button {
                Task { await viewModel.captureUtterance() }
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.largeTitle)
                    .symbolEffect(.pulse, isActive: viewModel.isResponding)
            }
            .disabled(viewModel.isResponding)
            .accessibilityLabel("Speak")
        }
        .padding(ParloSpacing.md)
        .background(ParloPalette.cardPaper.color)
    }
}

struct MessageBubble: View {
    let message: ConversationViewModel.Message
    let onDismissCorrection: () -> Void

    var body: some View {
        VStack(alignment: message.author == .learner ? .trailing : .leading, spacing: ParloSpacing.xs) {
            bubble
            if let naturalness = message.naturalness {
                NaturalnessMeter(naturalness: naturalness)
            }
            if let suggestion = message.visibleCorrection {
                CorrectionChip(suggestion: suggestion, onDismiss: onDismissCorrection)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.author == .learner ? .trailing : .leading)
        .transition(.scale(scale: 0.9, anchor: message.author == .learner ? .bottomTrailing : .bottomLeading)
            .combined(with: .opacity))
    }

    private var bubble: some View {
        Text(message.text)
            .font(ParloTypography.bubble)
            .foregroundStyle(
                message.author == .learner ? Color.white : ParloPalette.espressoInk.color,
            )
            .padding(.horizontal, ParloSpacing.md)
            .padding(.vertical, ParloSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ParloRadius.bubble)
                    .fill(message.author == .learner
                        ? ParloPalette.terracotta.color
                        : Color.white.opacity(0.85)),
            )
    }
}

/// Corrections are calm suggestions in teal — semantically reserved, never
/// red, always dismissible.
struct CorrectionChip: View {
    let suggestion: CorrectionSuggestion
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: ParloSpacing.xs) {
            Image(systemName: "leaf")
            Text("\(suggestion.originalSpan) → \(suggestion.correctedSpan)")
                .font(ParloTypography.chip)
            Text(suggestion.category.rawValue)
                .font(ParloTypography.caption)
                .opacity(0.7)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .accessibilityLabel("Dismiss suggestion")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ParloSpacing.md)
        .padding(.vertical, ParloSpacing.xs)
        .background(Capsule().fill(ParloPalette.correctionTeal.color))
    }
}

/// The naturalness meter fills like ink soaking into paper.
struct NaturalnessMeter: View {
    let naturalness: Naturalness
    @State private var fill: Double = 0

    var body: some View {
        HStack(spacing: ParloSpacing.xs) {
            Capsule()
                .fill(ParloPalette.cardPaper.color)
                .frame(width: 72, height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(ParloPalette.olive.color)
                            .frame(width: geometry.size.width * fill)
                    }
                }
                .clipShape(Capsule())
            Text(naturalness.note)
                .font(ParloTypography.caption)
                .foregroundStyle(ParloPalette.olive.color)
        }
        .onAppear {
            withAnimation(.easeOut(duration: ParloMotion.inkFillDuration)) {
                fill = naturalness.score
            }
        }
        .accessibilityLabel("Naturalness \(Int(naturalness.score * 100)) percent")
    }
}
