import Foundation

struct AnalysisPollingService {
    let pollingIntervalNanoseconds: UInt64
    let timeoutNanoseconds: UInt64

    enum PollingError: LocalizedError {
        case timedOut

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "Timed out while waiting for latest analysis."
            }
        }
    }

    init(
        pollingIntervalNanoseconds: UInt64 = 1_000_000_000,
        timeoutNanoseconds: UInt64 = 12_000_000_000
    ) {
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func pollLatestResult(
        sessionID: String,
        repository: any PracticeRepository
    ) async throws -> PracticeLatestResult {
        let startDate = Date()

        while true {
            try Task.checkCancellation()

            let elapsedNanoseconds = UInt64(
                max(0, Date().timeIntervalSince(startDate)) * 1_000_000_000
            )
            if elapsedNanoseconds >= timeoutNanoseconds {
                throw PollingError.timedOut
            }

            let latestResult = try await repository.fetchLatestResult(sessionID: sessionID)
            if latestResult.analysis.state != .loading {
                return latestResult
            }

            try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
        }
    }
}
