import Foundation

struct AppEnvironment {
    let backendBaseURL: URL
    let quoteRepository: any QuoteRepository

    static var runtime: AppEnvironment {
        let configuredURL =
            Bundle.main.object(forInfoDictionaryKey: "QUOTEAPP_BACKEND_BASE_URL") as? String ??
            ProcessInfo.processInfo.environment["QUOTEAPP_BACKEND_BASE_URL"] ??
            "http://127.0.0.1:8000"

        let fallbackURL = URL(string: "http://127.0.0.1:8000")!
        let backendBaseURL = URL(string: configuredURL) ?? fallbackURL

        return AppEnvironment(
            backendBaseURL: backendBaseURL,
            quoteRepository: QuoteRepositoryImpl(
                quoteService: QuoteService(baseURL: backendBaseURL)
            )
        )
    }
}
