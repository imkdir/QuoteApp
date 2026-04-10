import Combine
import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    private enum PracticeFlowError: LocalizedError {
        case repositoryUnavailable

        var errorDescription: String? {
            switch self {
            case .repositoryUnavailable:
                return "Practice repository is not configured."
            }
        }
    }

    @Published var sessionState: MainSessionState
    @Published var isQuotePickerPresented: Bool
    @Published var practiceStatusMessage: String
    @Published var spokenTokenCount: Int
    @Published var feedbackSheetAnalysis: PracticeAnalysis?
    @Published var tutorPlaybackState: TutorPlaybackState
    @Published var quotes: [Quote]
    @Published var isLoadingQuotes: Bool
    @Published var quoteLoadingErrorMessage: String?

    private let quoteRepository: (any QuoteRepository)?
    private let practiceRepository: (any PracticeRepository)?
    private let analysisPollingService: AnalysisPollingService?

    private var sessionStartTask: Task<String, Error>?
    private var resultPollingTask: Task<Void, Never>?
    private var activeLoadingAttemptID: UUID?
    private var nextMockResultCursor: Int
    private let mockResultOrder: [AnalysisState] = [.info, .perfect, .unavailable]

    init(
        quotes: [Quote] = MockQuotes.all,
        quoteRepository: (any QuoteRepository)? = nil,
        practiceRepository: (any PracticeRepository)? = nil,
        analysisPollingService: AnalysisPollingService? = nil,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        spokenTokenCount: Int = 0,
        feedbackSheetAnalysis: PracticeAnalysis? = nil,
        tutorPlaybackState: TutorPlaybackState = .pausedOrFinished,
        isLoadingQuotes: Bool = false,
        quoteLoadingErrorMessage: String? = nil,
        nextMockResultCursor: Int = 0
    ) {
        self.quotes = quotes
        self.quoteRepository = quoteRepository
        self.practiceRepository = practiceRepository
        self.analysisPollingService = analysisPollingService
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "Tap Repeat to advance spoken words."
        self.spokenTokenCount = spokenTokenCount
        self.feedbackSheetAnalysis = feedbackSheetAnalysis
        self.tutorPlaybackState = tutorPlaybackState
        self.isLoadingQuotes = isLoadingQuotes
        self.quoteLoadingErrorMessage = quoteLoadingErrorMessage
        self.nextMockResultCursor = nextMockResultCursor
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
            hasAttemptHistory: latestAnalysis != nil
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
        latestVisibleReviewAttempt?.analysis
    }

    private var latestVisibleReviewAttempt: PracticeAttempt? {
        guard let attempts = sessionState.practiceSession?.attempts else {
            return nil
        }

        return attempts.reversed().first { attempt in
            guard !attempt.isSupersededForUI,
                  let analysis = attempt.analysis else {
                return false
            }

            switch analysis.state {
            case .loading:
                return attempt.id == activeLoadingAttemptID
            case .info, .perfect, .unavailable:
                return true
            }
        }
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
        loadQuotesIfNeeded()
    }

    func closeQuotePicker() {
        isQuotePickerPresented = false
    }

    func retryQuoteLoading() {
        loadQuotes(force: true)
    }

    func selectQuote(_ quote: Quote) {
        sessionStartTask?.cancel()
        sessionStartTask = nil
        resultPollingTask?.cancel()
        resultPollingTask = nil
        activeLoadingAttemptID = nil

        sessionState = .practice(PracticeSession(quote: quote))
        isQuotePickerPresented = false
        spokenTokenCount = 0
        tutorPlaybackState = .pausedOrFinished
        feedbackSheetAnalysis = nil
        practiceStatusMessage = "All words are dimmed. Tap Repeat to mock playback."

        guard practiceRepository != nil else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await self.ensurePracticeSessionID(for: quote)
            } catch is CancellationError {
                return
            } catch {
                guard self.sessionState.selectedQuote?.id == quote.id else {
                    return
                }
                self.practiceStatusMessage = "Could not start practice session. Review may be unavailable."
            }
        }
    }

    private func loadQuotesIfNeeded() {
        guard quoteRepository != nil else {
            return
        }

        guard quotes.isEmpty else {
            return
        }

        guard !isLoadingQuotes else {
            return
        }

        loadQuotes(force: true)
    }

    private func loadQuotes(force: Bool) {
        guard let quoteRepository else {
            return
        }

        if !force && !quotes.isEmpty {
            return
        }

        guard !isLoadingQuotes else {
            return
        }

        isLoadingQuotes = true
        quoteLoadingErrorMessage = nil

        Task {
            do {
                let backendQuotes = try await quoteRepository.fetchQuotes()
                quotes = backendQuotes
                quoteLoadingErrorMessage = nil
            } catch {
                quoteLoadingErrorMessage = "Could not load quotes. Check backend and retry."
            }

            isLoadingQuotes = false
        }
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

        supersedeActiveLoadingAttemptForUI()

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

        if let latestAnalysis {
            practiceStatusMessage = statusMessage(for: latestAnalysis.state)
        } else {
            practiceStatusMessage = "Recording dismissed. Back to default controls."
        }
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
        activeLoadingAttemptID = attemptID

        practiceStatusMessage = "Reviewing latest attempt."
        feedbackSheetAnalysis = nil

        resultPollingTask?.cancel()
        resultPollingTask = nil

        guard let selectedQuote = sessionState.selectedQuote,
              let practiceRepository,
              let analysisPollingService else {
            resolveMockAnalysis(for: attemptID)
            return
        }

        resultPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sessionID = try await self.ensurePracticeSessionID(for: selectedQuote)
                let latestResult = try await analysisPollingService.pollLatestResult(
                    sessionID: sessionID,
                    repository: practiceRepository
                )
                self.applyBackendResult(latestResult, toLocalAttemptID: attemptID)
            } catch is CancellationError {
                return
            } catch AnalysisPollingService.PollingError.timedOut {
                self.applyUnavailableResult(
                    toLocalAttemptID: attemptID,
                    message: "Review timed out for this attempt."
                )
            } catch {
                self.applyUnavailableResult(
                    toLocalAttemptID: attemptID,
                    message: "Review unavailable. Could not fetch latest attempt result."
                )
            }
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
            practiceStatusMessage = "Review is still in progress."
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
        guard let quote = sessionState.selectedQuote else {
            return
        }

        let outcome = mockResultOrder[nextMockResultCursor]
        nextMockResultCursor = (nextMockResultCursor + 1) % mockResultOrder.count

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else {
                return
            }

            guard !self.isAttemptSupersededForUI(attemptID) else {
                return
            }

            let analysis = self.mockAnalysis(for: quote, state: outcome)
            self.updateAnalysis(analysis, forAttemptID: attemptID, backendAttemptID: nil)
            self.practiceStatusMessage = self.statusMessage(for: outcome)
            self.activeLoadingAttemptID = nil
        }
    }

    private func ensurePracticeSessionID(for quote: Quote) async throws -> String {
        if let existingSessionID = sessionState.practiceSession?.backendSessionID {
            return existingSessionID
        }

        if let sessionStartTask {
            return try await sessionStartTask.value
        }

        guard let practiceRepository else {
            throw PracticeFlowError.repositoryUnavailable
        }

        let startTask = Task<String, Error> {
            let start = try await practiceRepository.startSession(
                quoteID: quote.id,
                quoteText: quote.fullText
            )
            return start.sessionID
        }
        sessionStartTask = startTask

        do {
            let startedSessionID = try await startTask.value
            sessionStartTask = nil

            guard sessionState.selectedQuote?.id == quote.id else {
                return startedSessionID
            }

            updatePracticeSession { session in
                session.backendSessionID = startedSessionID
            }

            return startedSessionID
        } catch {
            sessionStartTask = nil
            throw error
        }
    }

    private func applyBackendResult(
        _ latestResult: PracticeLatestResult,
        toLocalAttemptID attemptID: UUID
    ) {
        guard !isAttemptSupersededForUI(attemptID) else {
            return
        }

        updatePracticeSession { session in
            if session.backendSessionID == nil {
                session.backendSessionID = latestResult.sessionID
            }

            guard let index = session.attempts.firstIndex(where: { $0.id == attemptID }) else {
                return
            }

            session.attempts[index].backendAttemptID = latestResult.attemptID
            session.attempts[index].analysis = latestResult.analysis
        }

        if latestResult.analysis.state != .loading {
            activeLoadingAttemptID = nil
        }
        practiceStatusMessage = statusMessage(for: latestResult.analysis.state)
    }

    private func applyUnavailableResult(
        toLocalAttemptID attemptID: UUID,
        message: String
    ) {
        guard !isAttemptSupersededForUI(attemptID) else {
            return
        }

        let unavailable = PracticeAnalysis(
            state: .unavailable,
            feedbackText: message
        )
        updateAnalysis(unavailable, forAttemptID: attemptID, backendAttemptID: nil)
        activeLoadingAttemptID = nil
        practiceStatusMessage = "Review unavailable."
    }

    private func updateAnalysis(
        _ analysis: PracticeAnalysis,
        forAttemptID attemptID: UUID,
        backendAttemptID: String?
    ) {
        updatePracticeSession { session in
            guard let index = session.attempts.firstIndex(where: { $0.id == attemptID }) else {
                return
            }

            session.attempts[index].analysis = analysis
            if let backendAttemptID {
                session.attempts[index].backendAttemptID = backendAttemptID
            }
        }
    }

    private func supersedeActiveLoadingAttemptForUI() {
        guard let activeLoadingAttemptID else {
            return
        }

        resultPollingTask?.cancel()
        resultPollingTask = nil

        updatePracticeSession { session in
            guard let index = session.attempts.firstIndex(where: { $0.id == activeLoadingAttemptID }) else {
                return
            }

            if session.attempts[index].analysis?.state == .loading {
                session.attempts[index].isSupersededForUI = true
            }
        }

        self.activeLoadingAttemptID = nil
    }

    private func isAttemptSupersededForUI(_ attemptID: UUID) -> Bool {
        sessionState.practiceSession?
            .attempts
            .first(where: { $0.id == attemptID })?
            .isSupersededForUI ?? false
    }

    private func statusMessage(for state: AnalysisState) -> String {
        switch state {
        case .loading:
            return "Reviewing latest attempt."
        case .info:
            return "Reviewed (info): words marked on the quote."
        case .perfect:
            return "Reviewed (perfect): no marked words."
        case .unavailable:
            return "Review unavailable."
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
    static func runtime(environment: AppEnvironment = .runtime) -> MainViewModel {
        MainViewModel(
            quotes: [],
            quoteRepository: environment.quoteRepository,
            practiceRepository: environment.practiceRepository,
            analysisPollingService: environment.analysisPollingService,
            quoteLoadingErrorMessage: nil
        )
    }

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

        if state == .loading {
            viewModel.activeLoadingAttemptID = attempt.id
        }

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
