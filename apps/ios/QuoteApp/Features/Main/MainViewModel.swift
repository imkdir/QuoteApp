import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published var sessionState: MainSessionState
    @Published var isQuotePickerPresented: Bool
    @Published var practiceStatusMessage: String
    @Published var spokenTokenCount: Int
    @Published var markedTokens: [MarkedToken]

    let quotes: [Quote]

    init(
        quotes: [Quote] = MockQuotes.all,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        spokenTokenCount: Int = 0,
        markedTokens: [MarkedToken] = []
    ) {
        self.quotes = quotes
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "Tap Repeat to advance spoken words."
        self.spokenTokenCount = spokenTokenCount
        self.markedTokens = markedTokens
    }

    var currentQuoteTokens: [QuoteToken] {
        guard let selectedQuote = sessionState.selectedQuote else {
            return []
        }

        return selectedQuote.makeTokens(
            spokenCount: spokenTokenCount,
            markedTokenIndexes: Set(markedTokens.map(\.index))
        )
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
        spokenTokenCount = 0
        markedTokens = []
        practiceStatusMessage = "All words are dimmed. Tap Repeat to mock playback."
    }

    func repeatTapped() {
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        spokenTokenCount = min(spokenTokenCount + 3, selectedQuote.wordCount)

        if spokenTokenCount >= selectedQuote.wordCount {
            practiceStatusMessage = "Playback mock reached the end."
        } else {
            practiceStatusMessage = "Playback mock advanced to word \(spokenTokenCount)."
        }
    }

    func recordTapped() {
        spokenTokenCount = 0
        markedTokens = []
        practiceStatusMessage = "Progress reset. All words are dimmed again."
    }

    func reviewTapped() {
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        if markedTokens.isEmpty {
            markedTokens = sampleMarkedTokens(for: selectedQuote)
            practiceStatusMessage = "Mock review: sample words are now underlined."
        } else {
            markedTokens = []
            practiceStatusMessage = "Mock review cleared."
        }
    }

    private func sampleMarkedTokens(for quote: Quote) -> [MarkedToken] {
        let markedWordSet = Set(quote.mockMarkedNormalizedTokens)

        return quote.makeTokens(spokenCount: spokenTokenCount, markedTokenIndexes: [])
            .filter { markedWordSet.contains($0.normalizedText) }
            .map { MarkedToken(index: $0.index, normalizedText: $0.normalizedText) }
    }
}

extension MainViewModel {
    static var previewStart: MainViewModel {
        MainViewModel()
    }

    static var previewPractice: MainViewModel {
        previewPracticePartiallySpoken
    }

    static var previewPracticeAllDimmed: MainViewModel {
        let viewModel = MainViewModel()
        if let firstQuote = viewModel.quotes.first {
            viewModel.selectQuote(firstQuote)
        }
        return viewModel
    }

    static var previewPracticePartiallySpoken: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.repeatTapped()
        viewModel.repeatTapped()
        return viewModel
    }

    static var previewPracticeMarked: MainViewModel {
        let viewModel = MainViewModel.previewPracticePartiallySpoken
        viewModel.reviewTapped()
        return viewModel
    }
}
