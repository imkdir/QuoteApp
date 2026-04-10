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
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.sessionState {
        case .start:
            StartView(onPickQuote: viewModel.openQuotePicker)
                .padding(24)

        case let .practice(quote):
            practiceView(quote: quote)
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
                recordingToolbarState: viewModel.recordingToolbarState,
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
            MainScreen(viewModel: .previewStart)
                .previewDisplayName("Start State")

            MainScreen(viewModel: .previewActionStateSpeaking)
                .previewDisplayName("Speaking")

            MainScreen(viewModel: .previewActionStatePaused)
                .previewDisplayName("Paused/Finished")

            MainScreen(viewModel: .previewActionStateRecording)
                .previewDisplayName("Recording")

            MainScreen(viewModel: .previewActionStateSendReady)
                .previewDisplayName("Stopped/Send Ready")

            MainScreen(viewModel: .previewActionStateReviewing)
                .previewDisplayName("Reviewing")

            MainScreen(viewModel: .previewActionStateReviewedInfo)
                .previewDisplayName("Reviewed Info")

            MainScreen(viewModel: .previewActionStateReviewedPerfect)
                .previewDisplayName("Reviewed Perfect")

            MainScreen(viewModel: .previewActionStateUnavailable)
                .previewDisplayName("Unavailable")
        }
    }
}
#endif
