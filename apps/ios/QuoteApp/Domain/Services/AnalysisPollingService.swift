import Foundation

struct AnalysisPollingService {
    let pollingIntervalNanoseconds: UInt64

    init(pollingIntervalNanoseconds: UInt64 = 1_000_000_000) {
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
    }

    func pollLatestResult(
        sessionID: String,
        repository: any PracticeRepository
    ) async throws -> PracticeLatestResult {
        while true {
            try Task.checkCancellation()

            let latestResult = try await repository.fetchLatestResult(sessionID: sessionID)
            if latestResult.analysis.state != .loading {
                return latestResult
            }

            try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
        }
    }
}
