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

@MainActor
final class LiveKitSessionManager: ObservableObject {
    @Published private(set) var connectionState: LiveKitConnectionState = .disconnected

    private let tokenProvider: any LiveKitTokenProviding

#if canImport(LiveKit)
    private let room: Room
#endif

    init(tokenProvider: any LiveKitTokenProviding) {
        self.tokenProvider = tokenProvider

#if canImport(LiveKit)
        self.room = Room()
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
                room.disconnect()
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

    func disconnect() {
#if canImport(LiveKit)
        room.disconnect()
#endif
        connectionState = .disconnected
    }
}
