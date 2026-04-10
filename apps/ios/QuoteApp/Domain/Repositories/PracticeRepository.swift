import Foundation

protocol PracticeRepository {
    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart
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
