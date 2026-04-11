import Foundation

struct AppEnvironment {
    let backendBaseURL: URL
    let quoteRepository: any QuoteRepository
    let practiceRepository: any PracticeRepository
    let analysisPollingService: AnalysisPollingService
    let liveKitSessionManager: LiveKitSessionManager
    let audioSessionManager: AudioSessionManager
    let userRecordingManager: UserRecordingManager
    let tutorPlaybackManager: TutorPlaybackManager
    let tutorAudioCache: TutorAudioCache

    @MainActor
    static var runtime: AppEnvironment {
        let fallbackURLString = "http://127.0.0.1:8000"
        let configuredURL =
            ProcessInfo.processInfo.environment["QUOTEAPP_BACKEND_BASE_URL"] ??
            (Bundle.main.object(forInfoDictionaryKey: "QUOTEAPP_BACKEND_BASE_URL") as? String) ??
            fallbackURLString

        let fallbackURL = URL(string: fallbackURLString)!
        let backendBaseURL = URL(string: configuredURL) ?? fallbackURL
        let tokenProvider = LiveKitTokenProvider(baseURL: backendBaseURL)

        return AppEnvironment(
            backendBaseURL: backendBaseURL,
            quoteRepository: QuoteRepositoryImpl(
                quoteService: QuoteService(baseURL: backendBaseURL)
            ),
            practiceRepository: PracticeRepositoryImpl(
                practiceService: PracticeService(baseURL: backendBaseURL)
            ),
            analysisPollingService: AnalysisPollingService(),
            liveKitSessionManager: LiveKitSessionManager(tokenProvider: tokenProvider),
            audioSessionManager: AudioSessionManager(),
            userRecordingManager: UserRecordingManager(),
            tutorPlaybackManager: TutorPlaybackManager(),
            tutorAudioCache: TutorAudioCache()
        )
    }
}
