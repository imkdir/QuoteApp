import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published var sessionState: MainSessionState
    @Published var isQuotePickerPresented: Bool
    @Published var practiceStatusMessage: String
    @Published var spokenTokenCount: Int
    @Published var markedTokens: [MarkedToken]
    @Published var actionToolbarState: ActionToolbarState
    @Published var recordingToolbarState: RecordingInputToolbarState

    let quotes: [Quote]

    private var nextSendOutcomeCursor: Int = 0
    private let sendOutcomeOrder: [ActionToolbarState] = [.reviewedInfo, .reviewedPerfect, .unavailable]

    init(
        quotes: [Quote] = MockQuotes.all,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        spokenTokenCount: Int = 0,
        markedTokens: [MarkedToken] = [],
        actionToolbarState: ActionToolbarState = .default,
        recordingToolbarState: RecordingInputToolbarState = .recording
    ) {
        self.quotes = quotes
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "Tap Repeat to advance spoken words."
        self.spokenTokenCount = spokenTokenCount
        self.markedTokens = markedTokens
        self.actionToolbarState = actionToolbarState
        self.recordingToolbarState = recordingToolbarState
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
        actionToolbarState = .default
        recordingToolbarState = .recording
        practiceStatusMessage = "All words are dimmed. Tap Repeat to mock playback."
    }

    func playbackTapped() {
        guard sessionState.isPractice else {
            return
        }

        switch actionToolbarState {
        case .speaking:
            actionToolbarState = .pausedOrFinished
            practiceStatusMessage = "Playback paused (mock)."

        case .recording, .recordedReadyToSend:
            break

        default:
            actionToolbarState = .speaking
            advanceSpokenProgress()
        }
    }

    func recordTapped() {
        guard sessionState.isPractice else {
            return
        }

        actionToolbarState = .recording
        recordingToolbarState = .recording
        practiceStatusMessage = "Recording started (mock)."
    }

    func stopRecordingTapped() {
        guard actionToolbarState == .recording else {
            return
        }

        recordingToolbarState = .stopped
        actionToolbarState = .recordedReadyToSend
        practiceStatusMessage = "Recording stopped. Ready to send (mock)."
    }

    func closeRecordingTapped() {
        guard actionToolbarState == .recording || actionToolbarState == .recordedReadyToSend else {
            return
        }

        recordingToolbarState = .recording
        actionToolbarState = .default
        practiceStatusMessage = "Recording dismissed. Back to default controls."
    }

    func sendTapped() {
        guard actionToolbarState == .recordedReadyToSend else {
            return
        }

        actionToolbarState = .reviewing

        let nextOutcome = sendOutcomeOrder[nextSendOutcomeCursor]
        nextSendOutcomeCursor = (nextSendOutcomeCursor + 1) % sendOutcomeOrder.count
        applyReviewOutcome(nextOutcome)

        recordingToolbarState = .recording
    }

    func reviewTapped() {
        guard sessionState.isPractice else {
            return
        }

        switch actionToolbarState {
        case .reviewing:
            break
        case .reviewedInfo:
            applyReviewOutcome(.reviewedPerfect)
        case .reviewedPerfect:
            applyReviewOutcome(.unavailable)
        case .unavailable:
            applyReviewOutcome(.reviewedInfo)
        default:
            actionToolbarState = .reviewing
            practiceStatusMessage = "Reviewing (mock)."
        }
    }

    private func advanceSpokenProgress() {
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        spokenTokenCount = min(spokenTokenCount + 3, selectedQuote.wordCount)

        if spokenTokenCount >= selectedQuote.wordCount {
            actionToolbarState = .pausedOrFinished
            practiceStatusMessage = "Playback finished (mock)."
        } else {
            practiceStatusMessage = "Tutor speaking mock advanced to word \(spokenTokenCount)."
        }
    }

    private func applyReviewOutcome(_ outcome: ActionToolbarState) {
        actionToolbarState = outcome

        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        switch outcome {
        case .reviewedInfo:
            markedTokens = sampleMarkedTokens(for: selectedQuote)
            practiceStatusMessage = "Reviewed (info): sample words are underlined."
        case .reviewedPerfect:
            markedTokens = []
            practiceStatusMessage = "Reviewed (perfect): no marked words."
        case .unavailable:
            markedTokens = []
            practiceStatusMessage = "Review unavailable (mock)."
        default:
            break
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
        viewModel.playbackTapped()
        viewModel.playbackTapped()
        return viewModel
    }

    static var previewPracticeMarked: MainViewModel {
        let viewModel = MainViewModel.previewPracticePartiallySpoken
        viewModel.applyReviewOutcome(.reviewedInfo)
        return viewModel
    }

    static var previewActionStateSpeaking: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.actionToolbarState = .speaking
        return viewModel
    }

    static var previewActionStatePaused: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.actionToolbarState = .pausedOrFinished
        return viewModel
    }

    static var previewActionStateRecording: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.actionToolbarState = .recording
        viewModel.recordingToolbarState = .recording
        return viewModel
    }

    static var previewActionStateSendReady: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.actionToolbarState = .recordedReadyToSend
        viewModel.recordingToolbarState = .stopped
        return viewModel
    }

    static var previewActionStateReviewing: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.actionToolbarState = .reviewing
        return viewModel
    }

    static var previewActionStateReviewedInfo: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.applyReviewOutcome(.reviewedInfo)
        return viewModel
    }

    static var previewActionStateReviewedPerfect: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.applyReviewOutcome(.reviewedPerfect)
        return viewModel
    }

    static var previewActionStateUnavailable: MainViewModel {
        let viewModel = MainViewModel.previewPracticeAllDimmed
        viewModel.applyReviewOutcome(.unavailable)
        return viewModel
    }
}
