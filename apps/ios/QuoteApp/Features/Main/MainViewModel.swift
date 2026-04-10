import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published var sessionState: MainSessionState
    @Published var isQuotePickerPresented: Bool
    @Published var practiceStatusMessage: String
    @Published var spokenTokenCount: Int
    @Published var feedbackSheetAnalysis: PracticeAnalysis?
    @Published var tutorPlaybackState: TutorPlaybackState

    let quotes: [Quote]

    private var nextMockResultCursor: Int
    private let mockResultOrder: [AnalysisState] = [.info, .perfect, .unavailable]
    private var pendingMockOutcomes: [UUID: AnalysisState]

    init(
        quotes: [Quote] = MockQuotes.all,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        spokenTokenCount: Int = 0,
        feedbackSheetAnalysis: PracticeAnalysis? = nil,
        tutorPlaybackState: TutorPlaybackState = .pausedOrFinished,
        nextMockResultCursor: Int = 0,
        pendingMockOutcomes: [UUID: AnalysisState] = [:]
    ) {
        self.quotes = quotes
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "Tap Repeat to advance spoken words."
        self.spokenTokenCount = spokenTokenCount
        self.feedbackSheetAnalysis = feedbackSheetAnalysis
        self.tutorPlaybackState = tutorPlaybackState
        self.nextMockResultCursor = nextMockResultCursor
        self.pendingMockOutcomes = pendingMockOutcomes
    }

    var actionToolbarState: ActionToolbarState {
        guard let session = sessionState.practiceSession else {
            return ActionToolbarState(
                tutorPlaybackState: tutorPlaybackState,
                localRecordingDraftState: nil,
                latestAttemptReviewState: .none,
                hasAttemptHistory: false
            )
        }

        return ActionToolbarState(
            tutorPlaybackState: tutorPlaybackState,
            localRecordingDraftState: session.localRecordingDraft?.state,
            latestAttemptReviewState: latestAttemptReviewState,
            hasAttemptHistory: !session.attempts.isEmpty
        )
    }

    var latestAttemptReviewState: LatestAttemptReviewState {
        guard let latestAnalysis = latestAnalysis else {
            return .none
        }

        switch latestAnalysis.state {
        case .loading:
            return .loading
        case .info:
            return .info
        case .perfect:
            return .perfect
        case .unavailable:
            return .unavailable
        }
    }

    var latestAnalysis: PracticeAnalysis? {
        sessionState.practiceSession?.latestAnalysis
    }

    var currentQuoteTokens: [QuoteToken] {
        guard let selectedQuote = sessionState.selectedQuote else {
            return []
        }

        let baseTokens = selectedQuote.makeTokens(spokenCount: spokenTokenCount, markedTokenIndexes: [])
        let markedWordSet = Set(markedWordsFromLatestAnalysis)

        let markedIndexes = Set(
            baseTokens
                .filter { markedWordSet.contains($0.normalizedText) }
                .map(\.index)
        )

        return selectedQuote.makeTokens(spokenCount: spokenTokenCount, markedTokenIndexes: markedIndexes)
    }

    func openQuotePicker() {
        isQuotePickerPresented = true
    }

    func closeQuotePicker() {
        isQuotePickerPresented = false
    }

    func selectQuote(_ quote: Quote) {
        sessionState = .practice(PracticeSession(quote: quote))
        isQuotePickerPresented = false
        spokenTokenCount = 0
        tutorPlaybackState = .pausedOrFinished
        feedbackSheetAnalysis = nil
        practiceStatusMessage = "All words are dimmed. Tap Repeat to mock playback."
    }

    func playbackTapped() {
        guard sessionState.isPractice else {
            return
        }

        guard sessionState.practiceSession?.localRecordingDraft == nil else {
            return
        }

        if tutorPlaybackState == .speaking {
            tutorPlaybackState = .pausedOrFinished
            practiceStatusMessage = "Playback paused (mock)."
            return
        }

        tutorPlaybackState = .speaking
        advanceSpokenProgress()
    }

    func recordTapped() {
        guard sessionState.isPractice else {
            return
        }

        let reference = "local-draft-\(Int(Date().timeIntervalSince1970))"

        updatePracticeSession { session in
            session.localRecordingDraft = LocalRecordingDraft(
                recordingReference: reference,
                state: .recording
            )
        }

        feedbackSheetAnalysis = nil
        tutorPlaybackState = .pausedOrFinished
        practiceStatusMessage = "Recording started (mock)."
    }

    func stopRecordingTapped() {
        guard sessionState.isPractice else {
            return
        }

        updatePracticeSession { session in
            guard var localDraft = session.localRecordingDraft else {
                return
            }

            localDraft.state = .stopped
            session.localRecordingDraft = localDraft
        }

        practiceStatusMessage = "Recording stopped. Ready to send (mock)."
    }

    func closeRecordingTapped() {
        guard sessionState.isPractice else {
            return
        }

        updatePracticeSession { session in
            session.localRecordingDraft = nil
        }

        practiceStatusMessage = "Recording dismissed. Back to default controls."
    }

    func sendTapped() {
        guard sessionState.isPractice else {
            return
        }

        guard let localDraft = sessionState.practiceSession?.localRecordingDraft,
              localDraft.state == .stopped else {
            return
        }

        let attemptID = UUID()
        let newAttempt = PracticeAttempt(
            id: attemptID,
            recordingReference: localDraft.recordingReference,
            analysis: PracticeAnalysis(
                state: .loading,
                feedbackText: "Reviewing your latest attempt."
            )
        )

        updatePracticeSession { session in
            session.localRecordingDraft = nil
            session.attempts.append(newAttempt)
        }

        let nextOutcome = mockResultOrder[nextMockResultCursor]
        nextMockResultCursor = (nextMockResultCursor + 1) % mockResultOrder.count
        pendingMockOutcomes[attemptID] = nextOutcome

        practiceStatusMessage = "Reviewing latest attempt (mock)."
        feedbackSheetAnalysis = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.resolveMockAnalysis(for: attemptID)
        }
    }

    func reviewTapped() {
        guard sessionState.isPractice else {
            return
        }

        guard let latestAnalysis = latestAnalysis else {
            practiceStatusMessage = "No review result yet."
            return
        }

        switch latestAnalysis.state {
        case .loading:
            return
        case .info, .perfect, .unavailable:
            feedbackSheetAnalysis = latestAnalysis
        }
    }

    private var markedWordsFromLatestAnalysis: [String] {
        guard let latestAnalysis = latestAnalysis,
              latestAnalysis.state == .info else {
            return []
        }

        return latestAnalysis.markedNormalizedTokens
    }

    private func advanceSpokenProgress() {
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        spokenTokenCount = min(spokenTokenCount + 3, selectedQuote.wordCount)

        if spokenTokenCount >= selectedQuote.wordCount {
            tutorPlaybackState = .pausedOrFinished
            practiceStatusMessage = "Playback finished (mock)."
        } else {
            practiceStatusMessage = "Tutor speaking mock advanced to word \(spokenTokenCount)."
        }
    }

    private func resolveMockAnalysis(for attemptID: UUID) {
        guard let practiceSession = sessionState.practiceSession,
              let attemptIndex = practiceSession.attempts.firstIndex(where: { $0.id == attemptID }) else {
            pendingMockOutcomes[attemptID] = nil
            return
        }

        guard let outcome = pendingMockOutcomes.removeValue(forKey: attemptID),
              let quote = sessionState.selectedQuote else {
            return
        }

        let analysis = mockAnalysis(for: quote, state: outcome)

        updatePracticeSession { session in
            guard attemptIndex < session.attempts.count else {
                return
            }

            session.attempts[attemptIndex].analysis = analysis
        }

        switch outcome {
        case .info:
            practiceStatusMessage = "Reviewed (info): words marked on the quote."
        case .perfect:
            practiceStatusMessage = "Reviewed (perfect): no marked words."
        case .unavailable:
            practiceStatusMessage = "Review unavailable (mock)."
        case .loading:
            practiceStatusMessage = "Reviewing latest attempt (mock)."
        }
    }

    private func mockAnalysis(for quote: Quote, state: AnalysisState) -> PracticeAnalysis {
        switch state {
        case .loading:
            return PracticeAnalysis(
                state: .loading,
                feedbackText: "Reviewing your latest attempt."
            )

        case .info:
            let markedWords = Array(quote.mockMarkedNormalizedTokens.prefix(3))
            return PracticeAnalysis(
                state: .info,
                markedNormalizedTokens: markedWords,
                feedbackText: "Good effort. Keep vowels steady and stress the marked words more clearly."
            )

        case .perfect:
            return PracticeAnalysis(
                state: .perfect,
                feedbackText: "Great pacing and pronunciation. This attempt sounds clear."
            )

        case .unavailable:
            return PracticeAnalysis(
                state: .unavailable,
                feedbackText: "We could not complete this review for the latest attempt."
            )
        }
    }

    private func updatePracticeSession(_ transform: (inout PracticeSession) -> Void) {
        guard case let .practice(currentSession) = sessionState else {
            return
        }

        var updatedSession = currentSession
        transform(&updatedSession)
        sessionState = .practice(updatedSession)
    }
}

extension MainViewModel {
    static var previewStart: MainViewModel {
        MainViewModel()
    }

    static var previewSpeakingNoAttempts: MainViewModel {
        let viewModel = MainViewModel()
        guard let quote = viewModel.quotes.first else {
            return viewModel
        }

        viewModel.sessionState = .practice(PracticeSession(quote: quote))
        viewModel.tutorPlaybackState = .speaking
        viewModel.practiceStatusMessage = "Tutor speaking mock is active."
        return viewModel
    }

    static var previewSpeakingWithOlderHistory: MainViewModel {
        let viewModel = makeLatestReviewPreview(state: .info, presentSheet: false)
        viewModel.tutorPlaybackState = .speaking
        viewModel.practiceStatusMessage = "Speaking while older attempt history exists."
        return viewModel
    }

    static var previewLoadingLatestAttempt: MainViewModel {
        makeLatestReviewPreview(state: .loading, presentSheet: false)
    }

    static var previewReviewedInfoLatestAttempt: MainViewModel {
        makeLatestReviewPreview(state: .info, presentSheet: false)
    }

    static var previewReviewedInfoPresented: MainViewModel {
        makeLatestReviewPreview(state: .info, presentSheet: true)
    }

    static var previewReviewedPerfectLatestAttempt: MainViewModel {
        makeLatestReviewPreview(state: .perfect, presentSheet: false)
    }

    static var previewUnavailableLatestAttempt: MainViewModel {
        makeLatestReviewPreview(state: .unavailable, presentSheet: false)
    }

    static var previewSendReadyWithOlderReviewedAttempt: MainViewModel {
        let viewModel = makeLatestReviewPreview(state: .info, presentSheet: false)
        viewModel.updatePracticeSession { session in
            session.localRecordingDraft = LocalRecordingDraft(
                recordingReference: "local-draft-preview",
                state: .stopped
            )
        }
        viewModel.practiceStatusMessage = "Recording stopped. Ready to send (mock)."
        return viewModel
    }

    private static func makeLatestReviewPreview(state: AnalysisState, presentSheet: Bool) -> MainViewModel {
        let viewModel = MainViewModel()
        guard let quote = viewModel.quotes.first else {
            return viewModel
        }

        let analysis = viewModel.mockAnalysis(for: quote, state: state)
        let attempt = PracticeAttempt(recordingReference: "attempt-preview", analysis: analysis)

        viewModel.sessionState = .practice(
            PracticeSession(
                quote: quote,
                attempts: [attempt],
                localRecordingDraft: nil
            )
        )

        viewModel.tutorPlaybackState = .pausedOrFinished
        viewModel.practiceStatusMessage = previewStatusMessage(for: state)

        if presentSheet {
            viewModel.feedbackSheetAnalysis = analysis
        }

        return viewModel
    }

    private static func previewStatusMessage(for state: AnalysisState) -> String {
        switch state {
        case .loading:
            return "Reviewing latest attempt (mock)."
        case .info:
            return "Reviewed (info): words marked on the quote."
        case .perfect:
            return "Reviewed (perfect): no marked words."
        case .unavailable:
            return "Review unavailable (mock)."
        }
    }
}
