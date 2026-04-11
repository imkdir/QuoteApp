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

@MainActor
final class LiveKitSessionManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: LiveKitConnectionState = .disconnected
    @Published private(set) var latestTutorTranscript: String?

    let tutorPlaybackEvents = PassthroughSubject<TutorPlaybackEvent, Never>()

    private let tokenProvider: any LiveKitTokenProviding

#if canImport(LiveKit)
    private let room: Room
    private var tutorAudioPublications: [Track.Sid: RemoteTrackPublication] = [:]
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
            let accessToken = try await tokenProvider.fetchToken(
                identity: identity,
                room: roomName,
                name: displayName
            )

            connectionState = .connecting(room: accessToken.room)

#if canImport(LiveKit)
            if room.connectionState != .disconnected {
                await room.disconnect()
            }

            try await room.connect(
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
