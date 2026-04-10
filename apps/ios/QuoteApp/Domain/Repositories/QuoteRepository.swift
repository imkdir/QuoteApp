import Foundation

protocol QuoteRepository {
    func fetchQuotes() async throws -> [Quote]
}

struct QuoteRepositoryImpl: QuoteRepository {
    let quoteService: QuoteService

    func fetchQuotes() async throws -> [Quote] {
        try await quoteService.fetchQuotes()
    }
}
