import SwiftUI

@MainActor
struct MainScreen: View {
    @StateObject private var viewModel: MainViewModel

    init(viewModel: MainViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $viewModel.feedbackSheetAnalysis) { analysis in
            TutorFeedbackSheet(analysis: analysis)
                .presentationDetents([.height(240), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.sessionState {
        case .start:
            StartView(onPickQuote: viewModel.openQuotePicker)
                .padding(24)

        case let .practice(session):
            practiceView(quote: session.quote)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    private func practiceView(quote: Quote?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let quote {
                QuoteTextView(tokens: viewModel.tokens(from: quote))
            } else {
                QuoteListView(
                    quotes: viewModel.quotes,
                    isLoading: viewModel.isLoadingQuotes && viewModel.quotes.isEmpty,
                    errorMessage: viewModel.quoteLoadingErrorMessage,
                    onSelect: viewModel.selectQuote,
                    onRetry: viewModel.retryQuoteLoading,
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("", systemImage: "text.quote", action: {
                    viewModel.openQuotePicker()
                })
                .foregroundStyle(.primary)
            }
            ToolbarItem(placement: .principal) {
                Image(systemName: viewModel.liveKitStatusSymbol)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                ActionStackView(
                    toolbarState: viewModel.actionToolbarState,
                    isPlaybackButtonDisabled: viewModel.isTutorAudioDownloadInFlight,
                    recordingWaveformLevels: viewModel.recordingWaveformLevels,
                    onPlaybackTapped: viewModel.playbackTapped,
                    onRecordTapped: viewModel.recordTapped,
                    onStopRecordingTapped: viewModel.stopRecordingTapped,
                    onCloseRecordingTapped: viewModel.closeRecordingTapped,
                    onSendTapped: viewModel.sendTapped,
                    onReviewTapped: viewModel.reviewTapped
                )
            }
        }
    }
}

#if DEBUG
struct MainScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainScreen(viewModel: .previewSpeakingNoAttempts)
                .previewDisplayName("Speaking (No Attempts)")

            MainScreen(viewModel: .previewSpeakingWithOlderHistory)
                .previewDisplayName("Speaking (With History)")

            MainScreen(viewModel: .previewLoadingLatestAttempt)
                .previewDisplayName("Latest Attempt Loading")

            MainScreen(viewModel: .previewReviewedInfoLatestAttempt)
                .previewDisplayName("Latest Attempt Reviewed Info")

            MainScreen(viewModel: .previewReviewedPerfectLatestAttempt)
                .previewDisplayName("Latest Attempt Reviewed Perfect")

            MainScreen(viewModel: .previewUnavailableLatestAttempt)
                .previewDisplayName("Latest Attempt Unavailable")

            MainScreen(viewModel: .previewSendReadyWithOlderReviewedAttempt)
                .previewDisplayName("Send Ready + Older Reviewed Attempt")

            MainScreen(viewModel: .previewMicrophoneDenied)
                .previewDisplayName("Microphone Denied")
        }
    }
}
#endif
