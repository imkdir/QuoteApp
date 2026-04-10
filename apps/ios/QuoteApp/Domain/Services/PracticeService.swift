import Foundation

struct PracticeSessionStart {
    let sessionID: String
    let quoteID: String
    let latestAttemptID: String?
    let latestResultState: AnalysisState?
}

struct PracticeLatestResult {
    let sessionID: String
    let quoteID: String
    let attemptID: String
    let recordingReference: String
    let analysis: PracticeAnalysis
}

struct PracticeService {
    enum PracticeServiceError: LocalizedError {
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
                return "Could not decode practice data from backend response."
            }
        }
    }

    private struct StartSessionRequestDTO: Encodable {
        let quoteID: String
        let quoteText: String?

        enum CodingKeys: String, CodingKey {
            case quoteID = "quote_id"
            case quoteText = "quote_text"
        }
    }

    private struct StartSessionResponseDTO: Decodable {
        let sessionID: String
        let quoteID: String
        let latestAttemptID: String?
        let latestResultStateRaw: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case quoteID = "quote_id"
            case latestAttemptID = "latest_attempt_id"
            case latestResultStateRaw = "latest_result_state"
        }
    }

    private struct MarkedTokenDTO: Decodable {
        let text: String
        let normalizedText: String

        enum CodingKeys: String, CodingKey {
            case text
            case normalizedText = "normalized_text"
        }
    }

    private struct LatestResultResponseDTO: Decodable {
        let sessionID: String
        let quoteID: String
        let attemptID: String
        let recordingReference: String
        let stateRaw: String
        let markedTokens: [MarkedTokenDTO]
        let feedbackText: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case quoteID = "quote_id"
            case attemptID = "attempt_id"
            case recordingReference = "recording_reference"
            case stateRaw = "state"
            case markedTokens = "marked_tokens"
            case feedbackText = "feedback_text"
        }
    }

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startSession(quoteID: String, quoteText: String?) async throws -> PracticeSessionStart {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent("start")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            StartSessionRequestDTO(
                quoteID: quoteID,
                quoteText: quoteText
            )
        )

        let data = try await perform(request: request)

        do {
            let dto = try JSONDecoder().decode(StartSessionResponseDTO.self, from: data)
            let mappedState = dto.latestResultStateRaw.flatMap(AnalysisState.init(rawValue:))

            return PracticeSessionStart(
                sessionID: dto.sessionID,
                quoteID: dto.quoteID,
                latestAttemptID: dto.latestAttemptID,
                latestResultState: mappedState
            )
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    func fetchLatestResult(sessionID: String) async throws -> PracticeLatestResult {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("result")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request: request)

        do {
            let dto = try JSONDecoder().decode(LatestResultResponseDTO.self, from: data)
            let mappedState = AnalysisState(backendValue: dto.stateRaw)

            let markedWords = dto.markedTokens.map { token in
                token.normalizedText.isEmpty ? token.text.lowercased() : token.normalizedText
            }

            return PracticeLatestResult(
                sessionID: dto.sessionID,
                quoteID: dto.quoteID,
                attemptID: dto.attemptID,
                recordingReference: dto.recordingReference,
                analysis: PracticeAnalysis(
                    state: mappedState,
                    markedNormalizedTokens: markedWords,
                    feedbackText: dto.feedbackText
                )
            )
        } catch let error as PracticeServiceError {
            throw error
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PracticeServiceError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PracticeServiceError.badStatusCode(httpResponse.statusCode)
        }

        return data
    }
}
