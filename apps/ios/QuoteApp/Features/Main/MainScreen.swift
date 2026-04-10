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

            QuoteTextView(quote: quote)

            Spacer(minLength: 20)

            ActionStackView(
                onRepeat: viewModel.repeatTapped,
                onRecord: viewModel.recordTapped,
                onReview: viewModel.reviewTapped
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

            MainScreen(viewModel: .previewPractice)
                .previewDisplayName("Practice State")
        }
    }
}
#endif
