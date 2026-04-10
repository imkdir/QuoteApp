import Combine
import Foundation

@MainActor
final class TutorPlaybackManager: ObservableObject {
    enum SessionBridgeState: Equatable {
        case idle
        case waitingForConnection
        case ready
        case failed(message: String)
    }

    @Published private(set) var bridgeState: SessionBridgeState = .idle

    func applyLiveKitConnectionState(_ state: LiveKitConnectionState) {
        switch state {
        case .disconnected:
            bridgeState = .idle
        case .requestingToken, .connecting:
            bridgeState = .waitingForConnection
        case .connected:
            bridgeState = .ready
        case let .failed(message):
            bridgeState = .failed(message: message)
        }
    }
}
