import Combine
import Foundation

#if canImport(LiveKit)
@preconcurrency import LiveKit
#endif

enum LiveKitConnectionState: Equatable {
    case disconnected
    case requestingToken
    case connecting(room: String)
    case connected(room: String, identity: String)
    case failed(message: String)
}

enum TutorPlaybackEvent: Equatable {
    case started(sessionID: String?, wordCount: Int, estimatedDurationSeconds: TimeInterval?)
    case finished(sessionID: String?)
    case stopped(sessionID: String?)
}

#if canImport(LiveKit)
private struct RoomHandle: @unchecked Sendable {
    let room: Room
}
#endif

@MainActor
final class LiveKitSessionManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: LiveKitConnectionState = .disconnected
    @Published private(set) var latestTutorTranscript: String?

    let tutorPlaybackEvents = PassthroughSubject<TutorPlaybackEvent, Never>()

    private let tokenProvider: any LiveKitTokenProviding

#if canImport(LiveKit)
    private let room: Room
    private var tutorAudioPublications: [Track.Sid: RemoteTrackPublication] = [:]
    private let tutorAudioReadyTopic = "quoteapp.tutor.audio.ready"
#endif

    init(tokenProvider: any LiveKitTokenProviding) {
        self.tokenProvider = tokenProvider

#if canImport(LiveKit)
        self.room = Room()
#endif
        super.init()

#if canImport(LiveKit)
        room.add(delegate: self)
#endif
    }

    func connect(
        identity: String,
        roomName: String,
        displayName: String? = nil
    ) async {
        if case let .connected(activeRoom, activeIdentity) = connectionState,
           activeRoom == roomName,
           activeIdentity == identity {
            return
        }

        connectionState = .requestingToken

        do {
            let accessToken = try await fetchTokenOffMainThread(
                identity: identity,
                roomName: roomName,
                displayName: displayName
            )

            connectionState = .connecting(room: accessToken.room)

#if canImport(LiveKit)
            try await reconnectRoomOffMainThread(
                url: accessToken.url,
                token: accessToken.token
            )

            connectionState = .connected(
                room: accessToken.room,
                identity: accessToken.identity
            )
#else
            connectionState = .failed(
                message: "LiveKit SDK is not linked in this build. Add client-sdk-swift package to connect."
            )
#endif
        } catch {
            connectionState = .failed(
                message: error.localizedDescription
            )
        }
    }

    private func fetchTokenOffMainThread(
        identity: String,
        roomName: String,
        displayName: String?
    ) async throws -> LiveKitAccessToken {
        let provider = tokenProvider
        return try await Task.detached(priority: .userInitiated) {
            try await provider.fetchToken(
                identity: identity,
                room: roomName,
                name: displayName
            )
        }.value
    }

    private func reconnectRoomOffMainThread(
        url: String,
        token: String
    ) async throws {
#if canImport(LiveKit)
        let roomHandle = RoomHandle(room: room)
        try await Task.detached(priority: .userInitiated) {
            let liveRoom = roomHandle.room
            if liveRoom.connectionState != .disconnected {
                await liveRoom.disconnect()
            }

            try await liveRoom.connect(
                url: url,
                token: token
            )
        }.value
#else
        _ = url
        _ = token
#endif
    }

    func disconnect() async {
#if canImport(LiveKit)
        await room.disconnect()
        tutorAudioPublications = [:]
#endif
        latestTutorTranscript = nil
        connectionState = .disconnected
    }

    func setTutorAudioPlaybackEnabled(_ enabled: Bool) async {
#if canImport(LiveKit)
        let publications = Array(tutorAudioPublications.values)
        for publication in publications {
            do {
                try await publication.set(subscribed: enabled)
                if enabled {
                    try await publication.set(enabled: true)
                }
            } catch {
                continue
            }
        }
#else
        _ = enabled
#endif
    }

#if canImport(LiveKit)
    private func rememberTutorAudioPublication(
        publication: RemoteTrackPublication,
        from participant: RemoteParticipant
    ) async {
        guard publication.kind == .audio else {
            return
        }

        guard isTutorParticipant(participant) else {
            return
        }

        tutorAudioPublications[publication.sid] = publication
        do {
            try await publication.set(subscribed: true)
            try await publication.set(enabled: true)
        } catch {
            return
        }
    }

    private func removeTutorAudioPublications(for participant: RemoteParticipant) {
        guard isTutorParticipant(participant) else {
            return
        }

        tutorAudioPublications.removeAll()
    }

    private func publishTutorAudioReady(
        publication: RemoteTrackPublication,
        from participant: RemoteParticipant
    ) async {
        guard publication.kind == .audio else {
            return
        }

        guard isTutorParticipant(participant) else {
            return
        }

        let payload: [String: String] = [
            "publication_sid": publication.sid.stringValue
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        do {
            try await room.localParticipant.publish(
                data: encoded,
                options: DataPublishOptions(
                    topic: tutorAudioReadyTopic,
                    reliable: true
                )
            )
        } catch {
            return
        }
    }

    private func isTutorParticipant(_ participant: RemoteParticipant?) -> Bool {
        guard let identity = participant?.identity?.stringValue else {
            return false
        }

        return identity.hasPrefix("tutor-")
    }
#endif

    private func handleTutorDataMessage(topic: String, payload: Data) {
        if topic == "quoteapp.tutor.quote_script",
           let script = String(data: payload, encoding: .utf8),
           !script.isEmpty {
            latestTutorTranscript = script
            return
        }

        guard topic == "quoteapp.tutor.playback" else {
            return
        }

        guard let raw = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return
        }

        let sessionID = raw["session_id"] as? String
        let eventName = raw["event"] as? String
        let wordCount = raw["word_count"] as? Int ?? 0
        let estimatedDurationSeconds = raw["estimated_duration_sec"] as? Double

        switch eventName {
        case "started":
            tutorPlaybackEvents.send(
                .started(
                    sessionID: sessionID,
                    wordCount: max(0, wordCount),
                    estimatedDurationSeconds: estimatedDurationSeconds
                )
            )
        case "finished":
            tutorPlaybackEvents.send(.finished(sessionID: sessionID))
        case "stopped":
            tutorPlaybackEvents.send(.stopped(sessionID: sessionID))
        default:
            return
        }
    }
}

#if canImport(LiveKit)
@MainActor
extension LiveKitSessionManager: RoomDelegate {
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didPublishTrack publication: RemoteTrackPublication
    ) {
        Task { @MainActor in
            await rememberTutorAudioPublication(publication: publication, from: participant)
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didSubscribeTrack publication: RemoteTrackPublication
    ) {
        _ = room
        Task { @MainActor in
            await publishTutorAudioReady(publication: publication, from: participant)
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType: EncryptionType
    ) {
        _ = room
        _ = participant
        _ = encryptionType

        Task { @MainActor in
            handleTutorDataMessage(topic: topic, payload: data)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        _ = room
        Task { @MainActor in
            removeTutorAudioPublications(for: participant)
        }
    }
}
#endif
