import SwiftUI

struct MainScreen: View {
    @StateObject private var viewModel: MainViewModel

    init(viewModel: MainViewModel = MainViewModel()) {
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
        .sheet(isPresented: $viewModel.isQuotePickerPresented) {
            QuotePickerSheet(
                quotes: viewModel.quotes,
                onSelect: viewModel.selectQuote,
                onClose: viewModel.closeQuotePicker
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    private func practiceView(quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BrandHeader()
                Button("Quotes") {
                    viewModel.openQuotePicker()
                }
                .buttonStyle(.bordered)
            }

            QuoteTextView(tokens: viewModel.currentQuoteTokens)

            Spacer(minLength: 20)

            ActionStackView(
                toolbarState: viewModel.actionToolbarState,
                onPlaybackTapped: viewModel.playbackTapped,
                onRecordTapped: viewModel.recordTapped,
                onStopRecordingTapped: viewModel.stopRecordingTapped,
                onCloseRecordingTapped: viewModel.closeRecordingTapped,
                onSendTapped: viewModel.sendTapped,
                onReviewTapped: viewModel.reviewTapped
            )

            Text(viewModel.practiceStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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

            MainScreen(viewModel: .previewReviewedInfoPresented)
                .previewDisplayName("Latest Info (Sheet Presented)")

            MainScreen(viewModel: .previewReviewedPerfectLatestAttempt)
                .previewDisplayName("Latest Attempt Reviewed Perfect")

            MainScreen(viewModel: .previewUnavailableLatestAttempt)
                .previewDisplayName("Latest Attempt Unavailable")

            MainScreen(viewModel: .previewSendReadyWithOlderReviewedAttempt)
                .previewDisplayName("Send Ready + Older Reviewed Attempt")
        }
    }
}
#endif
