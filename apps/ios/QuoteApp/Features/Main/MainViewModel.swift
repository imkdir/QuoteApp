import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published var sessionState: MainSessionState
    @Published var isQuotePickerPresented: Bool
    @Published var practiceStatusMessage: String

    let quotes: [Quote]

    init(
        quotes: [Quote] = MockQuotes.all,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false
    ) {
        self.quotes = quotes
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "Pick an action to simulate the flow."
    }

    func openQuotePicker() {
        isQuotePickerPresented = true
    }

    func closeQuotePicker() {
        isQuotePickerPresented = false
    }

    func selectQuote(_ quote: Quote) {
        sessionState = .practice(quote)
        isQuotePickerPresented = false
        practiceStatusMessage = "Selected: \(quote.bookTitle) (mock)."
    }

    func repeatTapped() {
        practiceStatusMessage = "Repeat tapped (mock)."
    }

    func recordTapped() {
        practiceStatusMessage = "Record tapped (mock)."
    }

    func reviewTapped() {
        practiceStatusMessage = "Review tapped (mock)."
    }
}

extension MainViewModel {
    static var previewStart: MainViewModel {
        MainViewModel()
    }

    static var previewPractice: MainViewModel {
        let viewModel = MainViewModel()
        if let firstQuote = viewModel.quotes.first {
            viewModel.selectQuote(firstQuote)
        }
        return viewModel
    }
}
