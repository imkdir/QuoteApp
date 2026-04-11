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
    @Published var isTutorAudioDownloadInFlight: Bool

    private let quoteRepository: (any QuoteRepository)?
    private let practiceRepository: (any PracticeRepository)?
    private let analysisPollingService: AnalysisPollingService?
    private let liveKitSessionManager: LiveKitSessionManager?
    private let audioSessionManager: AudioSessionManager?
    private let userRecordingManager: UserRecordingManager?
    private let tutorPlaybackManager: TutorPlaybackManager
    private let tutorAudioCache: TutorAudioCache

    private var sessionStartTask: Task<PracticeSessionStart, Error>?
    private var resultPollingTask: Task<Void, Never>?
    private var activeLoadingAttemptID: UUID?
    private let participantIdentity: String
    private var lastObservedPlaybackState: PlaybackState
    private var isTutorPlaybackCommandInFlight = false
    private var pendingTutorPlaybackRequestedAt: Date?
    private var pendingTutorPlaybackSessionID: String?
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
        tutorAudioCache: TutorAudioCache = TutorAudioCache(),
        sessionState: MainSessionState = .start,
        isQuotePickerPresented: Bool = false,
        feedbackSheetAnalysis: PracticeAnalysis? = nil,
        isLoadingQuotes: Bool = false,
        quoteLoadingErrorMessage: String? = nil,
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
        self.tutorAudioCache = tutorAudioCache
        self.sessionState = sessionState
        self.isQuotePickerPresented = isQuotePickerPresented
        self.practiceStatusMessage = "All words are dimmed. Tap Play to hear the tutor."
        self.feedbackSheetAnalysis = feedbackSheetAnalysis
        self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
        self.isLoadingQuotes = isLoadingQuotes
        self.quoteLoadingErrorMessage = quoteLoadingErrorMessage
        self.participantIdentity = participantIdentity
        self.lastObservedPlaybackState = self.tutorPlaybackManager.playbackState
        self.liveKitConnectionState = liveKitSessionManager?.connectionState ?? .disconnected
        self.recordingWaveformLevels = userRecordingManager?.meterLevels ?? Self.defaultWaveformLevels
        self.isTutorAudioDownloadInFlight = false

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
                hasVisibleReviewState: false
            )
        }

        return ActionToolbarState(
            playbackState: tutorPlaybackState,
            localRecordingDraftState: session.localRecordingDraft?.state,
            latestAttemptReviewState: latestAttemptReviewState,
            hasVisibleReviewState: latestVisibleReviewAttempt != nil
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

    var liveKitStatusBannerText: String? {
        switch liveKitConnectionState {
        case .disconnected:
            return nil
        case .requestingToken:
            return "Preparing LiveKit connection..."
        case let .connecting(room):
            return "Connecting to \(room)..."
        case .connected:
            return nil
        case let .failed(message):
            return "LiveKit connection error: \(message)"
        }
    }
    
    var liveKitStatusSymbol: String {
        switch liveKitConnectionState {
        case .disconnected:
            return "waveform.slash"
        case .requestingToken,
             .connecting:
            return "waveform.low"
        case .connected:
            return "waveform.mid"
        case .failed:
            return "waveform.badge.exclamationmark"
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
        let shouldStopPreviousTutorPlayback =
            tutorPlaybackState.isPlaying && tutorPlaybackManager.isUsingBackendStream

        sessionStartTask?.cancel()
        sessionStartTask = nil
        resultPollingTask?.cancel()
        resultPollingTask = nil
        activeLoadingAttemptID = nil
        isTutorAudioDownloadInFlight = false

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
                self.refreshLiveAPIStatusAfterRequestError(error)
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
                refreshLiveAPIStatusAfterRequestError(error)
                quoteLoadingErrorMessage = "Could not load quotes. Check backend and retry."
            }

            isLoadingQuotes = false
        }
    }

    func playbackTapped() {
        guard let selectedQuote = sessionState.selectedQuote else {
            return
        }

        guard !isInRecordingExclusiveMode else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard !self.isTutorPlaybackCommandInFlight else {
                return
            }

            let playbackStateBeforeCommand = self.tutorPlaybackState

            switch self.tutorPlaybackState {
            case .playing:
                self.isTutorPlaybackCommandInFlight = true
                self.isTutorAudioDownloadInFlight = false
                self.tutorPlaybackManager.pauseFromBackendStop()
                self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
                if self.tutorPlaybackManager.isUsingBackendStream {
                    await self.setTutorAudioPlaybackEnabled(false)
                    await self.stopTutorPlaybackForSessionIfPossible(self.currentBackendSessionID)
                }
                self.practiceStatusMessage = "Tutor playback paused."
                self.isTutorPlaybackCommandInFlight = false

            case .paused:
                if self.tutorPlaybackManager.resumeFromPausedPlaybackIfPossible() {
                    self.tutorPlaybackState = self.tutorPlaybackManager.playbackState
                    self.practiceStatusMessage = "Tutor playback resumed."
                    return
                }
                fallthrough

            case .idle, .finishedAtEnd:
                guard let practiceRepository else {
                    self.practiceStatusMessage = "Tutor playback is unavailable because backend practice services are not configured."
                    return
                }

                self.isTutorPlaybackCommandInFlight = true
                self.isTutorAudioDownloadInFlight = false
                defer {
                    self.isTutorAudioDownloadInFlight = false
                    self.isTutorPlaybackCommandInFlight = false
                }

                do {
                    let sessionID = try await self.ensurePracticeSessionID(for: selectedQuote)
                    guard self.sessionState.selectedQuote?.id == selectedQuote.id else {
                        return
                    }
                    await self.startLiveKitSetupIfStatusFailed(
                        for: selectedQuote,
                        sessionID: sessionID
                    )

                    let playbackIdentity = self.sessionState.practiceSession?.tutorPlaybackIdentity
                    if let playbackIdentity,
                       let cachedArtifact = self.tutorAudioCache.cachedAudioArtifact(
                           for: playbackIdentity
                       ) {
                        do {
                            try self.tutorPlaybackManager.beginPlaybackFromCachedAudioFile(
                                fileURL: cachedArtifact.fileURL,
                                wordCount: selectedQuote.wordCount,
                                estimatedDurationSeconds: cachedArtifact.metadata?.estimatedDurationSeconds,
                                rhythmWordEndTimes: cachedArtifact.metadata?.rhythmWordEndTimes ?? []
                            )
                            self.practiceStatusMessage = "Tutor playback started from device cache."
                            return
                        } catch {
                            try? FileManager.default.removeItem(at: cachedArtifact.fileURL)
                        }
                    }

                    self.isTutorAudioDownloadInFlight = true
                    let artifact: TutorPlaybackAudioArtifact
                    do {
                        artifact = try await practiceRepository.fetchTutorPlaybackAudioArtifact(
                            sessionID: sessionID
                        )
                    } catch {
                        guard self.isSessionExpiredError(error) else {
                            throw error
                        }
                        let recoveredSessionID = try await self.restartBackendSessionAndReconnect(
                            for: selectedQuote
                        )
                        artifact = try await practiceRepository.fetchTutorPlaybackAudioArtifact(
                            sessionID: recoveredSessionID
                        )
                    }
                    self.isTutorAudioDownloadInFlight = false
                    let cachedFileURL = try self.tutorAudioCache.storeAudioArtifact(
                        data: artifact.audioData,
                        playbackIdentity: artifact.playbackIdentity,
                        metadata: TutorAudioCache.CachedAudioMetadata(
                            estimatedDurationSeconds: artifact.estimatedDurationSeconds,
                            rhythmWordEndTimes: artifact.rhythmWordEndTimes
                        )
                    )
                    self.updatePracticeSession { session in
                        session.tutorPlaybackIdentity = artifact.playbackIdentity
                    }
                    try self.tutorPlaybackManager.beginPlaybackFromCachedAudioFile(
                        fileURL: cachedFileURL,
                        wordCount: artifact.wordCount > 0 ? artifact.wordCount : selectedQuote.wordCount,
                        estimatedDurationSeconds: artifact.estimatedDurationSeconds,
                        rhythmWordEndTimes: artifact.rhythmWordEndTimes
                    )

                    let isRestartFromBeginning = playbackStateBeforeCommand.isFinishedAtEnd
                    self.practiceStatusMessage = isRestartFromBeginning
                        ? "Tutor playback restarting from the beginning."
                        : "Tutor playback started."
                } catch {
                    self.refreshLiveAPIStatusAfterRequestError(error)
                    let fallbackStarted = await self.startTutorPlaybackViaLiveKitFallback(
                        for: selectedQuote,
                        playbackStateBeforeCommand: playbackStateBeforeCommand
                    )
                    if !fallbackStarted {
                        self.pendingTutorPlaybackRequestedAt = nil
                        self.pendingTutorPlaybackSessionID = nil
                        self.practiceStatusMessage = "Could not start tutor playback from backend."
                    }
                }
            }
        }
    }

    func recordTapped() {
        guard sessionState.isPractice else {
            return
        }

        guard !isInRecordingExclusiveMode else {
            return
        }

        let provisionalRecordingReference = "local-draft-\(UUID().uuidString)"
        updatePracticeSession { session in
            session.localRecordingDraft = LocalRecordingDraft(
                recordingReference: provisionalRecordingReference,
                state: .recording
            )
        }

        supersedeActiveLoadingAttemptForUI()
        feedbackSheetAnalysis = nil
        stopTutorPlaybackForRecordingPrecedence()

        guard let userRecordingManager else {
            updatePracticeSession { session in
                session.localRecordingDraft = nil
            }
            practiceStatusMessage = "Recording is unavailable in this build."
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
                    guard var localDraft = session.localRecordingDraft else {
                        return
                    }
                    localDraft.recordingReference = fileURL.path
                    localDraft.state = .recording
                    session.localRecordingDraft = localDraft
                }
                self.practiceStatusMessage = "Recording started."
            } catch UserRecordingManager.RecordingError.microphonePermissionDenied {
                self.updatePracticeSession { session in
                    session.localRecordingDraft = nil
                }
                self.practiceStatusMessage = "Microphone permission denied. Enable it in Settings to record."
            } catch {
                self.updatePracticeSession { session in
                    session.localRecordingDraft = nil
                }
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
                session.localRecordingDraft = nil
            }
            practiceStatusMessage = "No recording engine is available."
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
            applyUnavailableResult(
                toLocalAttemptID: attemptID,
                message: "Review unavailable. Backend practice services are not configured."
            )
            return
        }

        let draftFileURL = URL(fileURLWithPath: draftRecordingReference)
        resultPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sessionID = try await self.ensurePracticeSessionID(for: selectedQuote)
                await self.startLiveKitSetupIfStatusFailed(
                    for: selectedQuote,
                    sessionID: sessionID
                )
                let submission: PracticeAttemptSubmission
                do {
                    submission = try await practiceRepository.submitAttempt(
                        sessionID: sessionID,
                        recordingFileURL: draftFileURL,
                        originalRecordingReference: draftRecordingReference
                    )
                } catch {
                    guard self.isSessionExpiredError(error) else {
                        throw error
                    }
                    let recoveredSessionID = try await self.restartBackendSessionAndReconnect(
                        for: selectedQuote
                    )
                    submission = try await practiceRepository.submitAttempt(
                        sessionID: recoveredSessionID,
                        recordingFileURL: draftFileURL,
                        originalRecordingReference: draftRecordingReference
                    )
                }
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
                    sessionID: submission.sessionID,
                    repository: practiceRepository
                )
                self.applyBackendResult(latestResult, toLocalAttemptID: attemptID)
            } catch is CancellationError {
                return
            } catch AnalysisPollingService.PollingError.timedOut {
                self.refreshLiveAPIStatusAfterRequestError(
                    AnalysisPollingService.PollingError.timedOut
                )
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
                self.refreshLiveAPIStatusAfterRequestError(error)
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

    private func ensurePracticeSessionID(for quote: Quote) async throws -> String {
        if let existingSessionID = sessionState.practiceSession?.backendSessionID {
            return existingSessionID
        }

        guard let practiceRepository else {
            throw PracticeFlowError.repositoryUnavailable
        }

        do {
            let startTask: Task<PracticeSessionStart, Error>
            if let existingTask = sessionStartTask {
                startTask = existingTask
            } else {
                let newTask = Task<PracticeSessionStart, Error> {
                    try await practiceRepository.startSession(
                        quoteID: quote.id,
                        quoteText: quote.fullText
                    )
                }
                sessionStartTask = newTask
                startTask = newTask
            }

            let startedSession = try await startTask.value
            sessionStartTask = nil

            guard sessionState.selectedQuote?.id == quote.id else {
                return startedSession.sessionID
            }

            updatePracticeSession { session in
                session.backendSessionID = startedSession.sessionID
                if let tutorPlaybackIdentity = startedSession.tutorPlaybackIdentity,
                   !tutorPlaybackIdentity.isEmpty {
                    session.tutorPlaybackIdentity = tutorPlaybackIdentity
                }
            }

            return startedSession.sessionID
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
                   !self.isInRecordingExclusiveMode {
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

    private func startTutorPlaybackViaLiveKitFallback(
        for quote: Quote,
        playbackStateBeforeCommand: PlaybackState
    ) async -> Bool {
        guard let practiceRepository else {
            return false
        }

        do {
            let sessionID = try await ensurePracticeSessionID(for: quote)
            await connectLiveKitIfNeeded(for: quote, sessionID: sessionID)
            guard sessionState.selectedQuote?.id == quote.id else {
                return false
            }

            await setTutorAudioPlaybackEnabled(true)
            pendingTutorPlaybackRequestedAt = Date()
            pendingTutorPlaybackSessionID = sessionID
            do {
                try await practiceRepository.requestTutorPlayback(sessionID: sessionID)
            } catch {
                guard isSessionExpiredError(error) else {
                    throw error
                }
                let recoveredSessionID = try await restartBackendSessionAndReconnect(for: quote)
                pendingTutorPlaybackRequestedAt = Date()
                pendingTutorPlaybackSessionID = recoveredSessionID
                try await practiceRepository.requestTutorPlayback(sessionID: recoveredSessionID)
            }
            let isRestartFromBeginning = playbackStateBeforeCommand.isFinishedAtEnd
            practiceStatusMessage = isRestartFromBeginning
                ? "Tutor playback restarting from the beginning."
                : "Tutor playback requested."
            return true
        } catch {
            pendingTutorPlaybackRequestedAt = nil
            pendingTutorPlaybackSessionID = nil
            refreshLiveAPIStatusAfterRequestError(error)
            return false
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

    private var isInRecordingExclusiveMode: Bool {
        sessionState.practiceSession?.isInRecordingExclusiveMode ?? false
    }

    private func handleTutorPlaybackEvent(_ event: TutorPlaybackEvent) {
        switch event {
        case let .started(sessionID, wordCount, estimatedDurationSeconds):
            guard matchesCurrentSession(eventSessionID: sessionID) else {
                return
            }
            if let requestedAt = pendingTutorPlaybackRequestedAt,
               pendingTutorPlaybackSessionID == sessionID {
                let elapsedMs = Date().timeIntervalSince(requestedAt) * 1000
                NSLog(
                    "[TutorLatency][iOS] session=%@ request_to_started_ms=%.1f",
                    sessionID ?? "unknown",
                    elapsedMs
                )
            }
            pendingTutorPlaybackRequestedAt = nil
            pendingTutorPlaybackSessionID = nil

            guard !isInRecordingExclusiveMode else {
                stopTutorPlaybackForRecordingPrecedence()
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
            pendingTutorPlaybackRequestedAt = nil
            pendingTutorPlaybackSessionID = nil

            tutorPlaybackManager.markFinishedAtEndFromBackend()
            if !isInRecordingExclusiveMode {
                practiceStatusMessage = "Tutor playback finished."
            }

        case let .stopped(sessionID):
            guard matchesCurrentSession(eventSessionID: sessionID) else {
                return
            }
            pendingTutorPlaybackRequestedAt = nil
            pendingTutorPlaybackSessionID = nil

            guard !isInRecordingExclusiveMode else {
                tutorPlaybackManager.forceStopForRecording()
                tutorPlaybackState = tutorPlaybackManager.playbackState
                return
            }

            tutorPlaybackManager.markStoppedFromBackend()
            if !isInRecordingExclusiveMode {
                practiceStatusMessage = "Tutor playback paused."
            }
        }
    }

    private func stopTutorPlaybackForRecordingPrecedence() {
        let shouldStopBackendTransport = tutorPlaybackManager.isUsingBackendStream
        tutorPlaybackManager.forceStopForRecording()
        tutorPlaybackState = tutorPlaybackManager.playbackState

        Task { [weak self] in
            guard let self else {
                return
            }
            guard shouldStopBackendTransport else {
                return
            }
            await self.setTutorAudioPlaybackEnabled(false)
            await self.stopTutorPlaybackForSessionIfPossible(self.currentBackendSessionID)
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
            refreshLiveAPIStatusAfterRequestError(error)
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

    private func updatePracticeSession(_ transform: (inout PracticeSession) -> Void) {
        guard case let .practice(currentSession) = sessionState else {
            return
        }

        var updatedSession = currentSession
        transform(&updatedSession)
        sessionState = .practice(updatedSession)
    }

    private func isSessionExpiredError(_ error: Error) -> Bool {
        guard let serviceError = error as? PracticeService.PracticeServiceError else {
            return false
        }
        guard case let .badStatusCode(statusCode, detail) = serviceError else {
            return false
        }
        guard statusCode == 404 else {
            return false
        }

        let normalizedDetail = (detail ?? "").lowercased()
        if normalizedDetail.contains("session_not_found") || normalizedDetail.contains("session not found") {
            return true
        }

        // Backend can restart and return generic 404 detail; treat as expired session for recovery.
        return normalizedDetail.isEmpty
    }

    private func restartBackendSessionAndReconnect(for quote: Quote) async throws -> String {
        updatePracticeSession { session in
            session.backendSessionID = nil
            session.tutorPlaybackIdentity = nil
        }
        pendingTutorPlaybackRequestedAt = nil
        pendingTutorPlaybackSessionID = nil

        let recoveredSessionID = try await ensurePracticeSessionID(for: quote)
        await connectLiveKitIfNeeded(for: quote, sessionID: recoveredSessionID)
        return recoveredSessionID
    }

    private func startLiveKitSetupIfStatusFailed(
        for quote: Quote,
        sessionID: String
    ) async {
        guard case .failed = liveKitConnectionState else {
            return
        }

        await connectLiveKitIfNeeded(for: quote, sessionID: sessionID)
    }

    private func refreshLiveAPIStatusAfterRequestError(_ error: Error) {
        guard let message = liveAPIErrorMessage(from: error) else {
            return
        }

        let nextState = LiveKitConnectionState.failed(message: message)
        liveKitConnectionState = nextState
        tutorPlaybackManager.applyLiveKitConnectionState(nextState)
    }

    private func liveAPIErrorMessage(from error: Error) -> String? {
        if error is CancellationError {
            return nil
        }

        if let serviceError = error as? PracticeService.PracticeServiceError {
            return serviceError.errorDescription ?? "Practice API request failed."
        }

        if let serviceError = error as? QuoteService.QuoteServiceError {
            return serviceError.errorDescription ?? "Quotes API request failed."
        }

        if let tokenError = error as? LiveKitTokenProvider.TokenProviderError {
            return tokenError.errorDescription ?? "LiveKit token request failed."
        }

        if let pollingError = error as? AnalysisPollingService.PollingError {
            return pollingError.errorDescription ?? "Analysis polling failed."
        }

        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.localizedDescription
        }

        return nil
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
            tutorAudioCache: environment.tutorAudioCache,
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
        viewModel.practiceStatusMessage = "Recording stopped. Ready to send."
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

        let analysis = previewAnalysis(for: quote, state: state)
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
            return "Reviewing latest attempt."
        case .info:
            return "Reviewed (info): words marked on the quote."
        case .perfect:
            return "Reviewed (perfect): no marked words."
        case .unavailable:
            return "Review unavailable."
        }
    }

    private static func previewAnalysis(for quote: Quote, state: AnalysisState) -> PracticeAnalysis {
        switch state {
        case .loading:
            return PracticeAnalysis(
                state: .loading,
                feedbackText: "Reviewing your latest attempt."
            )
        case .info:
            return PracticeAnalysis(
                state: .info,
                markedNormalizedTokens: previewMarkedWords(for: quote),
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

    private static func previewMarkedWords(for quote: Quote) -> [String] {
        let normalized = quote.fullText
            .split(whereSeparator: { $0.isWhitespace })
            .map {
                $0.lowercased()
                    .replacingOccurrences(
                        of: "[^a-z0-9']",
                        with: "",
                        options: .regularExpression
                    )
            }
            .filter { !$0.isEmpty }
        return Array(normalized.prefix(3))
    }
}
