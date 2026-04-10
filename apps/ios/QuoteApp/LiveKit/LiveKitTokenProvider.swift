import Foundation

struct LiveKitAccessToken {
    let token: String
    let url: String
    let identity: String
    let room: String
}

protocol LiveKitTokenProviding {
    func fetchToken(identity: String, room: String, name: String?) async throws -> LiveKitAccessToken
}

struct LiveKitTokenProvider: LiveKitTokenProviding {
    enum TokenProviderError: LocalizedError {
        case invalidHTTPResponse
        case badStatusCode(Int)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidHTTPResponse:
                return "Invalid token endpoint response."
            case let .badStatusCode(code):
                return "LiveKit token endpoint returned status code \(code)."
            case .decodingFailed:
                return "Could not decode LiveKit token response."
            }
        }
    }

    private struct TokenRequestDTO: Encodable {
        let identity: String
        let room: String
        let name: String?
    }

    private struct TokenResponseDTO: Decodable {
        let token: String
        let url: String
        let identity: String
        let room: String
    }

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchToken(identity: String, room: String, name: String?) async throws -> LiveKitAccessToken {
        let endpoint = baseURL
            .appendingPathComponent("livekit")
            .appendingPathComponent("token")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TokenRequestDTO(identity: identity, room: room, name: name)
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenProviderError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TokenProviderError.badStatusCode(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
            return LiveKitAccessToken(
                token: decoded.token,
                url: decoded.url,
                identity: decoded.identity,
                room: decoded.room
            )
        } catch {
            throw TokenProviderError.decodingFailed
        }
    }
}
