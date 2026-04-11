import AVFoundation
import Combine
import Foundation

@MainActor
final class TutorPlaybackManager: NSObject, ObservableObject {
    enum SessionBridgeState: Equatable {
        case idle
        case waitingForConnection
        case ready
        case failed(message: String)
    }

    enum ActivePlaybackSource: Equatable {
        case none
        case backendStream
        case localCachedArtifact
    }

    enum PlaybackError: LocalizedError {
        case invalidLocalAudioFile
        case playbackStartFailed

        var errorDescription: String? {
            switch self {
            case .invalidLocalAudioFile:
                return "Cached tutor audio file is invalid."
            case .playbackStartFailed:
                return "Could not start cached tutor audio playback."
            }
        }
    }

    @Published private(set) var bridgeState: SessionBridgeState = .idle
    @Published private(set) var playbackState: PlaybackState
    @Published private(set) var activePlaybackSource: ActivePlaybackSource = .none

    private let timingCoordinator: PlaybackTimingCoordinator
    private var audioPlayer: AVAudioPlayer?

    var isUsingLocalAudio: Bool {
        activePlaybackSource == .localCachedArtifact
    }

    var isUsingBackendStream: Bool {
        activePlaybackSource == .backendStream
    }

    init(timingCoordinator: PlaybackTimingCoordinator? = nil) {
        let coordinator = timingCoordinator ?? PlaybackTimingCoordinator()
        self.timingCoordinator = coordinator
        self.playbackState = .idle(totalWordCount: coordinator.progress.totalWordCount)
        super.init()

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
        stopLocalAudioPlayback()
        activePlaybackSource = .none
        timingCoordinator.reset(totalWordCount: wordCount)
        playbackState = .idle(totalWordCount: max(0, wordCount))
    }

    func beginPlaybackFromBackendStart(
        wordCount: Int,
        estimatedDurationSeconds: TimeInterval?
    ) {
        stopLocalAudioPlayback()
        activePlaybackSource = .backendStream
        let clampedWordCount = max(0, wordCount)
        playbackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 0, totalWordCount: clampedWordCount)
        )
        timingCoordinator.startFromBeginning(
            totalWordCount: clampedWordCount,
            expectedDurationSeconds: estimatedDurationSeconds,
            completionBehavior: .waitForExplicitFinish
        )
    }

    func beginPlaybackFromCachedAudioFile(
        fileURL: URL,
        wordCount: Int,
        estimatedDurationSeconds: TimeInterval?,
        rhythmWordEndTimes: [TimeInterval]
    ) throws {
        stopLocalAudioPlayback()

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: fileURL)
        } catch {
            throw PlaybackError.invalidLocalAudioFile
        }

        player.delegate = self
        player.currentTime = 0
        player.prepareToPlay()
        guard player.play() else {
            throw PlaybackError.playbackStartFailed
        }

        audioPlayer = player
        activePlaybackSource = .localCachedArtifact

        let clampedWordCount = max(0, wordCount)
        playbackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 0, totalWordCount: clampedWordCount)
        )
        timingCoordinator.startFromBeginning(
            totalWordCount: clampedWordCount,
            expectedDurationSeconds: normalizedExpectedDuration(
                preferredDuration: estimatedDurationSeconds,
                fallbackPlayerDuration: player.duration
            ),
            completionBehavior: .waitForExplicitFinish,
            startDelaySeconds: 0,
            wordEndTimes: rhythmWordEndTimes
        )
    }

    func beginLocalDevelopmentFallbackPlayback(wordCount: Int) {
        stopLocalAudioPlayback()
        activePlaybackSource = .none
        let clampedWordCount = max(0, wordCount)
        playbackState = .playing(
            progress: PlaybackProgress(spokenWordCount: 0, totalWordCount: clampedWordCount)
        )
        timingCoordinator.startFromBeginning(
            totalWordCount: clampedWordCount,
            expectedDurationSeconds: nil,
            completionBehavior: .autoFinishWhenProgressReachesEnd
        )
    }

    func pauseFromBackendStop() {
        if activePlaybackSource == .localCachedArtifact {
            audioPlayer?.pause()
        }

        timingCoordinator.pause()
        switch playbackState {
        case .playing, .paused:
            playbackState = .paused(progress: timingCoordinator.progress)
        case .finishedAtEnd, .idle:
            return
        }
    }

    func markFinishedAtEndFromBackend() {
        stopLocalAudioPlayback()
        activePlaybackSource = .none
        timingCoordinator.finishAtEnd()
        playbackState = .finishedAtEnd(progress: timingCoordinator.progress)
    }

    func markStoppedFromBackend() {
        pauseFromBackendStop()
    }

    func forceStopForRecording() {
        guard !playbackState.isFinishedAtEnd else {
            return
        }

        stopLocalAudioPlayback()
        activePlaybackSource = .none
        timingCoordinator.finishAtEnd()
        playbackState = .finishedAtEnd(progress: timingCoordinator.progress)
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

    private func stopLocalAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func normalizedExpectedDuration(
        preferredDuration: TimeInterval?,
        fallbackPlayerDuration: TimeInterval
    ) -> TimeInterval? {
        if let preferredDuration, preferredDuration > 0 {
            return preferredDuration
        }

        return fallbackPlayerDuration > 0 ? fallbackPlayerDuration : nil
    }
}

extension TutorPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        _ = flag
        Task { @MainActor [weak self] in
            guard let self, player === self.audioPlayer else {
                return
            }

            self.audioPlayer = nil
            self.activePlaybackSource = .none
            self.timingCoordinator.finishAtEnd()
            self.playbackState = .finishedAtEnd(progress: self.timingCoordinator.progress)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        _ = error
        Task { @MainActor [weak self] in
            guard let self, player === self.audioPlayer else {
                return
            }

            self.audioPlayer = nil
            self.activePlaybackSource = .none
            self.timingCoordinator.pause()
            self.playbackState = .paused(progress: self.timingCoordinator.progress)
        }
    }
}
