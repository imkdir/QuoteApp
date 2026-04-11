import Foundation

struct PracticeSessionStart {
    let sessionID: String
    let quoteID: String
    let liveKitRoom: String?
    let latestAttemptID: String?
    let latestResultState: AnalysisState?
    let tutorPlaybackIdentity: String?
}

struct PracticeLatestResult {
    let sessionID: String
    let quoteID: String
    let attemptID: String
    let recordingReference: String
    let analysis: PracticeAnalysis
}

struct PracticeAttemptSubmission {
    let sessionID: String
    let quoteID: String
    let attemptID: String
    let recordingReference: String
    let state: AnalysisState
}

struct TutorPlaybackAudioArtifact {
    let sessionID: String
    let playbackIdentity: String
    let wordCount: Int
    let estimatedDurationSeconds: TimeInterval?
    let rhythmWordEndTimes: [TimeInterval]
    let audioData: Data
}

struct PracticeService {
    enum PracticeServiceError: LocalizedError {
        case invalidHTTPResponse
        case badStatusCode(Int, String?)
        case decodingFailed
        case failedToReadRecordingFile
        case emptyRecordingFile
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidHTTPResponse:
                return "Invalid response from backend."
            case let .badStatusCode(code, detail):
                if let detail, !detail.isEmpty {
                    return "Backend returned status code \(code): \(detail)"
                }
                return "Backend returned status code \(code)."
            case .decodingFailed:
                return "Could not decode practice data from backend response."
            case .failedToReadRecordingFile:
                return "Could not read the local recording file for submission."
            case .emptyRecordingFile:
                return "Cannot submit an empty recording."
            case let .requestFailed(message):
                return "Request failed: \(message)"
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
        let liveKitRoom: String?
        let latestAttemptID: String?
        let latestResultStateRaw: String?
        let tutorPlaybackIdentityRaw: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case quoteID = "quote_id"
            case liveKitRoom = "livekit_room"
            case latestAttemptID = "latest_attempt_id"
            case latestResultStateRaw = "latest_result_state"
            case tutorPlaybackIdentityRaw = "tutor_playback_identity"
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

    private struct SubmitAttemptResponseDTO: Decodable {
        let sessionID: String
        let quoteID: String
        let attemptID: String
        let recordingReference: String
        let stateRaw: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case quoteID = "quote_id"
            case attemptID = "attempt_id"
            case recordingReference = "recording_reference"
            case stateRaw = "state"
        }
    }

    private struct TutorPlaybackCommandResponseDTO: Decodable {
        let sessionID: String
        let status: String
        let message: String?
        let tutorPlaybackIdentityRaw: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case status
            case message
            case tutorPlaybackIdentityRaw = "tutor_playback_identity"
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
                liveKitRoom: dto.liveKitRoom,
                latestAttemptID: dto.latestAttemptID,
                latestResultState: mappedState,
                tutorPlaybackIdentity: dto.tutorPlaybackIdentityRaw
            )
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    func updateSessionQuote(
        sessionID: String,
        quoteID: String,
        quoteText: String?
    ) async throws -> PracticeSessionStart {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("quote")

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
                liveKitRoom: dto.liveKitRoom,
                latestAttemptID: dto.latestAttemptID,
                latestResultState: mappedState,
                tutorPlaybackIdentity: dto.tutorPlaybackIdentityRaw
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

            let markedWords = dto.markedTokens.compactMap { token in
                let source = token.normalizedText.isEmpty ? token.text : token.normalizedText
                let normalized = Self.normalizeMarkedToken(source)
                return normalized.isEmpty ? nil : normalized
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

    func requestTutorPlayback(sessionID: String) async throws {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("tutor")
            .appendingPathComponent("play")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request: request)

        do {
            _ = try JSONDecoder().decode(TutorPlaybackCommandResponseDTO.self, from: data)
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    func fetchTutorPlaybackAudioArtifact(sessionID: String) async throws -> TutorPlaybackAudioArtifact {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("tutor")
            .appendingPathComponent("audio")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            throw PracticeServiceError.requestFailed(
                nsError.localizedFailureReason ?? nsError.localizedDescription
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PracticeServiceError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PracticeServiceError.badStatusCode(
                httpResponse.statusCode,
                extractBackendDetail(from: data)
            )
        }

        guard
            let playbackIdentity = httpResponse.value(forHTTPHeaderField: "X-QuoteApp-Playback-Identity"),
            !playbackIdentity.isEmpty
        else {
            throw PracticeServiceError.decodingFailed
        }

        let wordCount = Int(httpResponse.value(forHTTPHeaderField: "X-QuoteApp-Word-Count") ?? "") ?? 0
        let estimatedDurationSeconds = Double(
            httpResponse.value(forHTTPHeaderField: "X-QuoteApp-Estimated-Duration-Sec") ?? ""
        )
        let rhythmWordEndTimes = decodeRhythmWordEndTimes(
            from: httpResponse.value(forHTTPHeaderField: "X-QuoteApp-Rhythm-B64")
        )

        return TutorPlaybackAudioArtifact(
            sessionID: sessionID,
            playbackIdentity: playbackIdentity,
            wordCount: max(0, wordCount),
            estimatedDurationSeconds: estimatedDurationSeconds,
            rhythmWordEndTimes: rhythmWordEndTimes,
            audioData: data
        )
    }

    func stopTutorPlayback(sessionID: String) async throws {
        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("tutor")
            .appendingPathComponent("stop")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request: request)

        do {
            _ = try JSONDecoder().decode(TutorPlaybackCommandResponseDTO.self, from: data)
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    func submitAttempt(
        sessionID: String,
        recordingFileURL: URL,
        originalRecordingReference: String
    ) async throws -> PracticeAttemptSubmission {
        let recordingData: Data
        do {
            recordingData = try Data(contentsOf: recordingFileURL)
        } catch {
            throw PracticeServiceError.failedToReadRecordingFile
        }

        guard !recordingData.isEmpty else {
            throw PracticeServiceError.emptyRecordingFile
        }

        let endpoint = baseURL
            .appendingPathComponent("practice")
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("attempt")
            .appendingPathComponent("submit")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(recordingFileURL.lastPathComponent, forHTTPHeaderField: "X-QuoteApp-Filename")
        request.setValue(originalRecordingReference, forHTTPHeaderField: "X-QuoteApp-Recording-Reference")
        request.httpBody = recordingData

        let data = try await perform(request: request)

        do {
            let dto = try JSONDecoder().decode(SubmitAttemptResponseDTO.self, from: data)
            return PracticeAttemptSubmission(
                sessionID: dto.sessionID,
                quoteID: dto.quoteID,
                attemptID: dto.attemptID,
                recordingReference: dto.recordingReference,
                state: AnalysisState(backendValue: dto.stateRaw)
            )
        } catch {
            throw PracticeServiceError.decodingFailed
        }
    }

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            throw PracticeServiceError.requestFailed(
                nsError.localizedFailureReason ?? nsError.localizedDescription
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PracticeServiceError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PracticeServiceError.badStatusCode(
                httpResponse.statusCode,
                extractBackendDetail(from: data)
            )
        }

        return data
    }

    private func extractBackendDetail(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = payload["detail"] {
            if let detailString = detail as? String, !detailString.isEmpty {
                return detailString
            }

            if let detailObject = detail as? [String: Any],
               let message = detailObject["message"] as? String,
               !message.isEmpty {
                return message
            }
        }

        if let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !body.isEmpty {
            return body
        }

        return nil
    }

    private func decodeRhythmWordEndTimes(from encodedValue: String?) -> [TimeInterval] {
        guard let encodedValue, !encodedValue.isEmpty else {
            return []
        }

        let padded = paddedBase64URLString(encodedValue)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let decodedData = Data(base64Encoded: padded) else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode([Double].self, from: decodedData) else {
            return []
        }

        var last: TimeInterval = 0
        return decoded.compactMap { raw in
            guard raw.isFinite else {
                return nil
            }
            let clamped = max(0, raw)
            guard clamped >= last else {
                return nil
            }
            last = clamped
            return clamped
        }
    }

    private func paddedBase64URLString(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else {
            return value
        }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private static func normalizeMarkedToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "[’‘`]", with: "'", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9']", with: "", options: .regularExpression)
    }
}
