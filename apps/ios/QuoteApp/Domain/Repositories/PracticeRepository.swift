import Foundation

protocol PracticeRepository {
    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart
    func updateSessionQuote(sessionID: String, quoteID: String, quoteText: String?) async throws -> PracticeSessionStart
    func requestTutorPlayback(sessionID: String) async throws
    func fetchTutorPlaybackAudioArtifact(sessionID: String) async throws -> TutorPlaybackAudioArtifact
    func stopTutorPlayback(sessionID: String) async throws
    func submitAttempt(
        sessionID: String,
        recordingFileURL: URL,
        originalRecordingReference: String
    ) async throws -> PracticeAttemptSubmission
    func fetchLatestResult(sessionID: String) async throws -> PracticeLatestResult
}

struct PracticeRepositoryImpl: PracticeRepository {
    let practiceService: PracticeService

    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart {
        try await practiceService.startSession(quoteID: quoteID, quoteText: quoteText)
    }

    func updateSessionQuote(sessionID: String, quoteID: String, quoteText: String?) async throws -> PracticeSessionStart {
        try await practiceService.updateSessionQuote(
            sessionID: sessionID,
            quoteID: quoteID,
            quoteText: quoteText
        )
    }

    func requestTutorPlayback(sessionID: String) async throws {
        try await practiceService.requestTutorPlayback(sessionID: sessionID)
    }

    func fetchTutorPlaybackAudioArtifact(sessionID: String) async throws -> TutorPlaybackAudioArtifact {
        try await practiceService.fetchTutorPlaybackAudioArtifact(sessionID: sessionID)
    }

    func stopTutorPlayback(sessionID: String) async throws {
        try await practiceService.stopTutorPlayback(sessionID: sessionID)
    }

    func submitAttempt(
        sessionID: String,
        recordingFileURL: URL,
        originalRecordingReference: String
    ) async throws -> PracticeAttemptSubmission {
        try await practiceService.submitAttempt(
            sessionID: sessionID,
            recordingFileURL: recordingFileURL,
            originalRecordingReference: originalRecordingReference
        )
    }

    func fetchLatestResult(sessionID: String) async throws -> PracticeLatestResult {
        try await practiceService.fetchLatestResult(sessionID: sessionID)
    }
}
