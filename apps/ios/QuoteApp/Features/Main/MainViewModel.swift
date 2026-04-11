import Combine
import CoreGraphics
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
    @Published var feedbackSheetAnalysis: PracticeAnalysis?
    @Published var tutorPlaybackState: PlaybackState
    @Published var quotes: [Quote]
    @Published var isLoadingQuotes: Bool
    @Published var quoteLoadingErrorMessage: String?
    @Published var liveKitConnectionState: LiveKitConnectionState
    @Published var recordingWaveformLevels: [CGFloat]

    private let quoteRepository: (any QuoteRepository)?
    private let practiceRepository: (any PracticeRepository)?
    private let analysisPollingService: AnalysisPollingService?
    private let liveKitSessionManager: LiveKitSessionManager?
    private let audioSessionManager: AudioSessionManager?
    private let userRecordingManager: UserRecordingManager?
    private let tutorPlaybackManager: TutorPlaybackManager

    private var sessionStartTask: Task<String, Error>?
    private var resultPollingTask: Task<Void, Never>?
    private var activeLoadingAttemptID: UUID?
    private var nextMockResultCursor: Int
    private let mockResultOrder: [AnalysisState] = [.info, .perfect, .unavailable]
    private let participantIdentity: String
    private var lastObservedPlaybackState: PlaybackState
    private var isTutorPlaybackCommandInFlight = false
    private var cancellables = Set<AnyCancellable>()

    init(
        quotes: [Quote] = MockQuotes.all,
        quoteRepository: (any QuoteRepository)? = nil,
        practiceRepository: (any PracticeRepository)? = nil,
        analysisPollingService: AnalysisPollingService? = nil,
        liveKitSessionManager: LiveKitSessionManager? = nil,
        audioSessionManager: AudioSessionManager? = nil,
        userRecordingManager: UserRecordingManager? = nil,
        tutorPlaybackManager: TutorPlaybackManager? = nil,
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        feedbackSheetAnalysis: PracticeAnalysis? = nil,
        isLoadingQuotes: Bool = false,
        quoteLoadingErrorMessage: String? = nil,
        nextMockResultCursor: Int = 0,
        participantIdentity: String = "ios-\(UUID().uuidString.prefix(8))"
    ) {
        self.quotes = quotes
        self.quoteRepository = quoteRepository
        self.practiceRepository = practiceRepository
        self.analysisPollingService = analysisPollingService
        self.liveKitSessionManager = liveKitSessionManager
        self.audioSessionManager = audioSessionManager
        self.userRecordingManager = userRecordingManager
        self.tutorPlaybackManager = tutorPlaybackManager ?? TutorPlaybackManager()
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "All words are dimmed. Tap Play to hear the tutor."
        self.feedbackSheetAnalysis = feedbackSheetAnalysis
        self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
        self.isLoadingQuotes = isLoadingQuotes
        self.quoteLoadingErrorMessage = quoteLoadingErrorMessage
        self.nextMockResultCursor = nextMockResultCursor
        self.participantIdentity = participantIdentity
        self.lastObservedPlaybackState = self.tutorPlaybackManager.playbackState
        self.liveKitConnectionState = liveKitSessionManager?.connectionState ?? .disconnected
        self.recordingWaveformLevels = userRecordingManager?.meterLevels ?? Self.defaultWaveformLevels

        let initialWordCount = sessionState.selectedQuoteWordCount
        let initialQuoteText = sessionState.selectedQuote?.fullText
        self.tutorPlaybackManager.prepareForQuote(
            wordCount: initialWordCount,
            quoteText: initialQuoteText
        )
        self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
        self.lastObservedPlaybackState = self.tutorPlaybackState

        bindTutorPlaybackState()
        bindLiveKitState()
        bindTutorPlaybackEvents()
        bindRecordingState()
    }

    var actionToolbarState: ActionToolbarState {
        guard let session = sessionState.practiceSession else {
            return ActionToolbarState(
                playbackState: tutorPlaybackState,
                localRecordingDraftState: nil,
                latestAttemptReviewState: .none,
                hasAttemptHistory: false
            )
        }

        return ActionToolbarState(
            playbackState: tutorPlaybackState,
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

        let spokenWordCount = tutorPlaybackState.spokenWordCount
        let baseTokens = selectedQuote.makeTokens(spokenCount: spokenWordCount, markedTokenIndexes: [])
        let markedWordSet = Set(markedWordsFromLatestAnalysis)

        let markedIndexes = Set(
            baseTokens
                .filter { markedWordSet.contains($0.normalizedText) }
                .map(\.index)
        )

        return selectedQuote.makeTokens(spokenCount: spokenWordCount, markedTokenIndexes: markedIndexes)
    }

    var liveKitStatusText: String {
        switch liveKitConnectionState {
        case .disconnected:
            return "LiveKit disconnected"
        case .requestingToken:
            return "LiveKit: requesting token..."
        case let .connecting(room):
            return "LiveKit: connecting to \(room)"
        case let .connected(room, identity):
            return "LiveKit connected (\(identity) in \(room))"
        case let .failed(message):
            return "LiveKit error: \(message)"
        }
    }

    var isLiveKitStatusError: Bool {
        if case .failed = liveKitConnectionState {
            return true
        }
        return false
    }

    private static let defaultWaveformLevels = Array(repeating: CGFloat(0.12), count: 16)

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
        let previousSessionID = sessionState.practiceSession?.backendSessionID
        let shouldStopPreviousTutorPlayback = tutorPlaybackState.isPlaying

        sessionStartTask?.cancel()
        sessionStartTask = nil
        resultPollingTask?.cancel()
        resultPollingTask = nil
        activeLoadingAttemptID = nil

        sessionState = .practice(PracticeSession(quote: quote))
        isQuotePickerPresented = false
        tutorPlaybackManager.prepareForQuote(
            wordCount: quote.wordCount,
            quoteText: quote.fullText
        )
        tutorPlaybackState = tutorPlaybackManager.playbackState
        feedbackSheetAnalysis = nil
        userRecordingManager?.clearRecording()
        recordingWaveformLevels = userRecordingManager?.meterLevels ?? Self.defaultWaveformLevels
        practiceStatusMessage = "All words are dimmed. Tap Play to hear the tutor."

        if shouldStopPreviousTutorPlayback {
            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.stopTutorPlaybackForSessionIfPossible(previousSessionID)
            }
        }

        guard practiceRepository != nil else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sessionID = try await self.ensurePracticeSessionID(for: quote)
                await self.connectLiveKitIfNeeded(for: quote, sessionID: sessionID)
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
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        guard sessionState.practiceSession?.localRecordingDraft == nil else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard !self.isTutorPlaybackCommandInFlight else {
                return
            }

            await self.connectLiveKitForSelectedQuoteIfNeeded(selectedQuote)
            guard self.sessionState.selectedQuote?.id == selectedQuote.id else {
                return
            }

            switch self.tutorPlaybackState {
            case .playing:
                self.isTutorPlaybackCommandInFlight = true
                await self.setTutorAudioPlaybackEnabled(false)
                self.tutorPlaybackManager.pauseFromBackendStop()
                self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
                await self.stopTutorPlaybackForSessionIfPossible(self.currentBackendSessionID)
                self.practiceStatusMessage = "Tutor playback paused."
                self.isTutorPlaybackCommandInFlight = false

            case .idle, .paused, .finishedAtEnd:
                guard let practiceRepository else {
                    self.tutorPlaybackManager.beginLocalDevelopmentFallbackPlayback(
                        wordCount: selectedQuote.wordCount
                    )
                    self.practiceStatusMessage =
                        "Development fallback: local quote timing is active (no backend tutor audio)."
                    return
                }

                do {
                    self.isTutorPlaybackCommandInFlight = true
                    let sessionID = try await self.ensurePracticeSessionID(for: selectedQuote)
                    await self.setTutorAudioPlaybackEnabled(true)
                    try await practiceRepository.requestTutorPlayback(sessionID: sessionID)
                    self.practiceStatusMessage = "Tutor playback requested."
                    self.isTutorPlaybackCommandInFlight = false
                } catch {
                    self.practiceStatusMessage = "Could not start tutor playback from backend."
                    self.isTutorPlaybackCommandInFlight = false
                }
            }
        }
    }

    func recordTapped() {
        guard sessionState.isPractice else {
            return
        }

        supersedeActiveLoadingAttemptForUI()
        feedbackSheetAnalysis = nil
        tutorPlaybackManager.forceStopForRecording()
        tutorPlaybackState = tutorPlaybackManager.playbackState

        Task { [weak self] in
            guard let self else {
                return
            }
            await self.setTutorAudioPlaybackEnabled(false)
            await self.stopTutorPlaybackForSessionIfPossible(self.currentBackendSessionID)
        }

        guard let userRecordingManager else {
            let reference = "local-draft-\(Int(Date().timeIntervalSince1970))"
            updatePracticeSession { session in
                session.localRecordingDraft = LocalRecordingDraft(
                    recordingReference: reference,
                    state: .recording
                )
            }
            practiceStatusMessage = "Recording started (mock)."
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let fileURL = try await userRecordingManager.startRecording(
                    audioSessionManager: self.audioSessionManager
                )
                self.updatePracticeSession { session in
                    session.localRecordingDraft = LocalRecordingDraft(
                        recordingReference: fileURL.path,
                        state: .recording
                    )
                }
                self.practiceStatusMessage = "Recording started."
            } catch UserRecordingManager.RecordingError.microphonePermissionDenied {
                self.practiceStatusMessage = "Microphone permission denied. Enable it in Settings to record."
            } catch {
                if let detail = userRecordingManager.lastErrorMessage, !detail.isEmpty {
                    self.practiceStatusMessage = detail
                } else {
                    self.practiceStatusMessage = "Could not start recording."
                }
            }
        }
    }

    func stopRecordingTapped() {
        guard sessionState.isPractice else {
            return
        }

        guard let userRecordingManager else {
            updatePracticeSession { session in
                guard var localDraft = session.localRecordingDraft else {
                    return
                }

                localDraft.state = .stopped
                session.localRecordingDraft = localDraft
            }

            practiceStatusMessage = "Recording stopped. Ready to send (mock)."
            return
        }

        do {
            let fileURL = try userRecordingManager.stopRecording()
            updatePracticeSession { session in
                session.localRecordingDraft = LocalRecordingDraft(
                    recordingReference: fileURL.path,
                    state: .stopped
                )
            }
            practiceStatusMessage = "Recording stopped. Ready to send."
        } catch {
            practiceStatusMessage = "No active recording to stop."
        }
    }

    func closeRecordingTapped() {
        guard sessionState.isPractice else {
            return
        }

        userRecordingManager?.clearRecording()
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

        let draftRecordingReference = localDraft.recordingReference
        let attemptID = UUID()
        let newAttempt = PracticeAttempt(
            id: attemptID,
            recordingReference: draftRecordingReference,
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
            userRecordingManager?.clearRecording()
            resolveMockAnalysis(for: attemptID)
            return
        }

        let draftFileURL = URL(fileURLWithPath: draftRecordingReference)
        resultPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sessionID = try await self.ensurePracticeSessionID(for: selectedQuote)
                let submission = try await practiceRepository.submitAttempt(
                    sessionID: sessionID,
                    recordingFileURL: draftFileURL,
                    originalRecordingReference: draftRecordingReference
                )
                self.updateAttemptSubmissionMetadata(
                    forAttemptID: attemptID,
                    backendAttemptID: submission.attemptID,
                    recordingReference: submission.recordingReference
                )

                if submission.state != .loading {
                    let immediateAnalysis = PracticeAnalysis(
                        state: submission.state,
                        feedbackText: "Review completed."
                    )
                    self.updateAnalysis(
                        immediateAnalysis,
                        forAttemptID: attemptID,
                        backendAttemptID: submission.attemptID
                    )
                    self.activeLoadingAttemptID = nil
                    self.practiceStatusMessage = self.statusMessage(for: submission.state)
                    self.userRecordingManager?.clearRecording()
                    return
                }

                self.userRecordingManager?.clearRecording()
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
                self.userRecordingManager?.clearRecording()
            } catch {
                let message: String
                if let serviceError = error as? PracticeService.PracticeServiceError {
                    switch serviceError {
                    case .failedToReadRecordingFile:
                        message = "Review unavailable. The local recording file could not be read."
                    case .emptyRecordingFile:
                        message = "Review unavailable. The recording file was empty."
                    case let .badStatusCode(code, detail):
                        if let detail, !detail.isEmpty {
                            message = "Review unavailable. Submission failed (\(code)): \(detail)"
                        } else {
                            message = "Review unavailable. Submission failed with status \(code)."
                        }
                    case let .requestFailed(detail):
                        message = "Review unavailable. Could not reach backend: \(detail)"
                    case .invalidHTTPResponse:
                        message = "Review unavailable. Backend returned an invalid response."
                    case .decodingFailed:
                        message = "Review unavailable. Backend response could not be decoded."
                    }
                } else {
                    message = "Review unavailable. Could not submit recording for review."
                }
                self.applyUnavailableResult(
                    toLocalAttemptID: attemptID,
                    message: message
                )
                self.userRecordingManager?.clearRecording()
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

    private func bindTutorPlaybackState() {
        tutorPlaybackManager.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    return
                }

                let previousState = self.lastObservedPlaybackState
                self.lastObservedPlaybackState = state
                self.tutorPlaybackState = state

                if previousState.isPlaying,
                   state.isFinishedAtEnd,
                   self.sessionState.practiceSession?.localRecordingDraft == nil {
                    self.practiceStatusMessage = "Tutor playback finished."
                }
            }
            .store(in: &cancellables)
    }

    private func bindLiveKitState() {
        guard let liveKitSessionManager else {
            return
        }

        liveKitSessionManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    return
                }
                self.liveKitConnectionState = state
                self.tutorPlaybackManager.applyLiveKitConnectionState(state)
            }
            .store(in: &cancellables)
    }

    private func bindTutorPlaybackEvents() {
        guard let liveKitSessionManager else {
            return
        }

        liveKitSessionManager.tutorPlaybackEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleTutorPlaybackEvent(event)
            }
            .store(in: &cancellables)
    }

    private func bindRecordingState() {
        guard let userRecordingManager else {
            return
        }

        userRecordingManager.$meterLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in
                self?.recordingWaveformLevels = levels
            }
            .store(in: &cancellables)
    }

    private func connectLiveKitForSelectedQuoteIfNeeded(_ quote: Quote) async {
        do {
            let sessionID = try await ensurePracticeSessionID(for: quote)
            await connectLiveKitIfNeeded(for: quote, sessionID: sessionID)
        } catch {
            practiceStatusMessage = "LiveKit connection failed. Tutor playback may be unavailable."
        }
    }

    private func connectLiveKitIfNeeded(
        for quote: Quote,
        sessionID: String
    ) async {
        guard let liveKitSessionManager else {
            return
        }

        let roomName = makeLiveKitRoomName(quoteID: quote.id, sessionID: sessionID)

        if case let .connected(activeRoom, _) = liveKitConnectionState,
           activeRoom == roomName {
            await liveKitSessionManager.setTutorAudioPlaybackEnabled(true)
            return
        }

        do {
            try audioSessionManager?.configureForVoiceInteraction()
        } catch {
            practiceStatusMessage = "Audio setup failed. LiveKit connection may fail."
        }

        await liveKitSessionManager.connect(
            identity: participantIdentity,
            roomName: roomName,
            displayName: "QuoteApp Learner"
        )
        await liveKitSessionManager.setTutorAudioPlaybackEnabled(true)
    }

    private func makeLiveKitRoomName(quoteID: String, sessionID: String) -> String {
        let raw = "practice-\(quoteID)-\(sessionID)"
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let sanitized = String(raw.filter { allowed.contains($0) })
        return sanitized.isEmpty ? "practice-default" : sanitized
    }

    private var currentBackendSessionID: String? {
        sessionState.practiceSession?.backendSessionID
    }

    private func handleTutorPlaybackEvent(_ event: TutorPlaybackEvent) {
        switch event {
        case let .started(sessionID, wordCount, estimatedDurationSeconds):
            guard matchesCurrentSession(eventSessionID: sessionID) else {
                return
            }

            let quoteWordCount = sessionState.selectedQuoteWordCount
            let totalWordCount = quoteWordCount > 0 ? quoteWordCount : wordCount
            tutorPlaybackManager.beginPlaybackFromBackendStart(
                wordCount: totalWordCount,
                estimatedDurationSeconds: estimatedDurationSeconds
            )
            practiceStatusMessage = "Tutor playback is active."

        case let .finished(sessionID):
            guard matchesCurrentSession(eventSessionID: sessionID) else {
                return
            }

            tutorPlaybackManager.markFinishedAtEndFromBackend()
            if sessionState.practiceSession?.localRecordingDraft == nil {
                practiceStatusMessage = "Tutor playback finished."
            }

        case let .stopped(sessionID):
            guard matchesCurrentSession(eventSessionID: sessionID) else {
                return
            }

            tutorPlaybackManager.markStoppedFromBackend()
            if sessionState.practiceSession?.localRecordingDraft == nil {
                practiceStatusMessage = "Tutor playback paused."
            }
        }
    }

    private func matchesCurrentSession(eventSessionID: String?) -> Bool {
        guard let eventSessionID else {
            return true
        }

        guard let currentBackendSessionID else {
            return false
        }

        return eventSessionID == currentBackendSessionID
    }

    private func stopTutorPlaybackForSessionIfPossible(_ sessionID: String?) async {
        guard let sessionID, let practiceRepository else {
            return
        }

        do {
            try await practiceRepository.stopTutorPlayback(sessionID: sessionID)
        } catch {
            return
        }
    }

    private func setTutorAudioPlaybackEnabled(_ enabled: Bool) async {
        guard let liveKitSessionManager else {
            return
        }

        await liveKitSessionManager.setTutorAudioPlaybackEnabled(enabled)
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
            session.attempts[index].recordingReference = latestResult.recordingReference
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

    private func updateAttemptSubmissionMetadata(
        forAttemptID attemptID: UUID,
        backendAttemptID: String,
        recordingReference: String
    ) {
        updatePracticeSession { session in
            guard let index = session.attempts.firstIndex(where: { $0.id == attemptID }) else {
                return
            }

            session.attempts[index].backendAttemptID = backendAttemptID
            session.attempts[index].recordingReference = recordingReference
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
    @MainActor
    static func runtime() -> MainViewModel {
        MainViewModel.runtime(environment: .runtime)
    }

    @MainActor
    static func runtime(environment: AppEnvironment) -> MainViewModel {
        MainViewModel(
            quotes: [],
            quoteRepository: environment.quoteRepository,
            practiceRepository: environment.practiceRepository,
            analysisPollingService: environment.analysisPollingService,
            liveKitSessionManager: environment.liveKitSessionManager,
            audioSessionManager: environment.audioSessionManager,
            userRecordingManager: environment.userRecordingManager,
            tutorPlaybackManager: environment.tutorPlaybackManager,
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
        viewModel.tutorPlaybackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 9, totalWordCount: quote.wordCount)
        )
        viewModel.practiceStatusMessage = "Tutor playback is active."
        return viewModel
    }

    static var previewSpeakingWithOlderHistory: MainViewModel {
        let viewModel = makeLatestReviewPreview(state: .info, presentSheet: false)
        let totalWordCount = viewModel.sessionState.selectedQuoteWordCount
        viewModel.tutorPlaybackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 7, totalWordCount: totalWordCount)
        )
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

    static var previewMicrophoneDenied: MainViewModel {
        let viewModel = MainViewModel()
        guard let quote = viewModel.quotes.first else {
            return viewModel
        }

        viewModel.sessionState = .practice(PracticeSession(quote: quote))
        viewModel.practiceStatusMessage = "Microphone permission denied. Enable it in Settings to record."
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

        viewModel.tutorPlaybackState = .finishedAtEnd(
            progress: PlaybackProgress(spokenWordCount: quote.wordCount, totalWordCount: quote.wordCount)
        )
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
