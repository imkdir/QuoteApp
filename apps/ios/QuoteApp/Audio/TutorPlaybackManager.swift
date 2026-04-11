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
    @Published private(set) var playbackState: PlaybackState

    private let timingCoordinator: PlaybackTimingCoordinator

    init(timingCoordinator: PlaybackTimingCoordinator? = nil) {
        let coordinator = timingCoordinator ?? PlaybackTimingCoordinator()
        self.timingCoordinator = coordinator
        self.playbackState = .idle(totalWordCount: coordinator.progress.totalWordCount)

        coordinator.onProgress = { [weak self] progress in
            guard let self else {
                return
            }

            switch self.playbackState {
            case .playing:
                self.playbackState = .playing(progress: progress)
            case .paused:
                self.playbackState = .paused(progress: progress)
            case .finishedAtEnd:
                self.playbackState = .finishedAtEnd(progress: progress)
            case .idle:
                self.playbackState = .idle(totalWordCount: progress.totalWordCount)
            }
        }

        coordinator.onFinishedAtEnd = { [weak self] progress in
            self?.playbackState = .finishedAtEnd(progress: progress)
        }
    }

    func prepareForQuote(wordCount: Int, quoteText: String?) {
        _ = quoteText
        timingCoordinator.reset(totalWordCount: wordCount)
        playbackState = .idle(totalWordCount: max(0, wordCount))
    }

    func beginPlaybackFromBackendStart(
        wordCount: Int,
        estimatedDurationSeconds: TimeInterval?
    ) {
        let clampedWordCount = max(0, wordCount)
        playbackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 0, totalWordCount: clampedWordCount)
        )
        timingCoordinator.startFromBeginning(
            totalWordCount: clampedWordCount,
            expectedDurationSeconds: estimatedDurationSeconds
        )
    }

    func beginLocalDevelopmentFallbackPlayback(wordCount: Int) {
        let clampedWordCount = max(0, wordCount)
        playbackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 0, totalWordCount: clampedWordCount)
        )
        timingCoordinator.startFromBeginning(
            totalWordCount: clampedWordCount,
            expectedDurationSeconds: nil
        )
    }

    func pauseFromBackendStop() {
        timingCoordinator.pause()
        playbackState = .paused(progress: timingCoordinator.progress)
    }

    func markFinishedAtEndFromBackend() {
        timingCoordinator.finishAtEnd()
        playbackState = .finishedAtEnd(progress: timingCoordinator.progress)
    }

    func markStoppedFromBackend() {
        pauseFromBackendStop()
    }

    func forceStopForRecording() {
        guard playbackState.isPlaying else {
            return
        }
        pauseFromBackendStop()
    }

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
