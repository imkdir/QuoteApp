import Foundation

struct QuoteService {
    enum QuoteServiceError: LocalizedError {
        case invalidHTTPResponse
        case badStatusCode(Int)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidHTTPResponse:
                return "Invalid response from backend."
            case let .badStatusCode(code):
                return "Backend returned status code \(code)."
            case .decodingFailed:
                return "Could not decode quotes from backend response."
            }
        }
    }

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchQuotes() async throws -> [Quote] {
        let endpoint = baseURL.appendingPathComponent("quotes")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuoteServiceError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw QuoteServiceError.badStatusCode(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([Quote].self, from: data)
        } catch {
            throw QuoteServiceError.decodingFailed
        }
    }
}
