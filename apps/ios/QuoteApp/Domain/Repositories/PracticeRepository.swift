import Foundation

protocol PracticeRepository {
    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart
    func fetchLatestResult(sessionID: String) async throws -> PracticeLatestResult
}

struct PracticeRepositoryImpl: PracticeRepository {
    let practiceService: PracticeService

    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart {
        try await practiceService.startSession(quoteID: quoteID, quoteText: quoteText)
    }

    func fetchLatestResult(sessionID: String) async throws -> PracticeLatestResult {
        try await practiceService.fetchLatestResult(sessionID: sessionID)
    }
}
