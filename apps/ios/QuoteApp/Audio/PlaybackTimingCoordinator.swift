import Combine
import Foundation

@MainActor
final class PlaybackTimingCoordinator {
    struct Configuration: Equatable {
        let wordsPerSecond: Double
        let tickInterval: TimeInterval

        static let `default` = Configuration(
            wordsPerSecond: 2.9,
            tickInterval: 0.12
        )
    }

    var onProgress: ((PlaybackProgress) -> Void)?
    var onFinishedAtEnd: ((PlaybackProgress) -> Void)?

    private(set) var progress: PlaybackProgress
    private let configuration: Configuration
    private var tickCancellable: AnyCancellable?
    private var runStartDate: Date?
    private var elapsedBeforeCurrentRun: TimeInterval = 0
    private var activeWordsPerSecond: Double

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.progress = PlaybackProgress(spokenWordCount: 0, totalWordCount: 0)
        self.activeWordsPerSecond = configuration.wordsPerSecond
    }

    func reset(totalWordCount: Int) {
        stopTicker()
        runStartDate = nil
        elapsedBeforeCurrentRun = 0
        activeWordsPerSecond = configuration.wordsPerSecond
        progress = PlaybackProgress(spokenWordCount: 0, totalWordCount: totalWordCount)
        onProgress?(progress)
    }

    func startFromBeginning(
        totalWordCount: Int,
        expectedDurationSeconds: TimeInterval? = nil
    ) {
        stopTicker()
        runStartDate = nil
        elapsedBeforeCurrentRun = 0
        progress = PlaybackProgress(spokenWordCount: 0, totalWordCount: totalWordCount)
        activeWordsPerSecond = wordsPerSecond(
            totalWordCount: totalWordCount,
            expectedDurationSeconds: expectedDurationSeconds
        )
        onProgress?(progress)

        guard progress.totalWordCount > 0 else {
            progress = progress.withSpokenWordCountAtEnd
            onProgress?(progress)
            onFinishedAtEnd?(progress)
            return
        }

        startTicker()
    }

    func resume() {
        guard !progress.isAtEnd else {
            return
        }

        startTicker()
    }

    func pause() {
        guard let runStartDate else {
            return
        }

        elapsedBeforeCurrentRun += Date().timeIntervalSince(runStartDate)
        self.runStartDate = nil
        stopTicker()
    }

    func finishAtEnd() {
        pause()
        progress = progress.withSpokenWordCountAtEnd
        onProgress?(progress)
        onFinishedAtEnd?(progress)
    }

    private func startTicker() {
        guard tickCancellable == nil else {
            return
        }

        runStartDate = Date()
        tickCancellable = Timer
            .publish(every: configuration.tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.handleTick(now: now)
            }
    }

    private func stopTicker() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }

    private func handleTick(now: Date) {
        guard let runStartDate else {
            return
        }

        let elapsed = elapsedBeforeCurrentRun + now.timeIntervalSince(runStartDate)
        let spokenWordCount = Int(floor(elapsed * activeWordsPerSecond))
        let nextProgress = PlaybackProgress(
            spokenWordCount: spokenWordCount,
            totalWordCount: progress.totalWordCount
        )

        guard nextProgress != progress else {
            return
        }

        progress = nextProgress
        onProgress?(progress)

        if progress.isAtEnd {
            elapsedBeforeCurrentRun = elapsed
            self.runStartDate = nil
            stopTicker()
            onFinishedAtEnd?(progress)
        }
    }

    private func wordsPerSecond(
        totalWordCount: Int,
        expectedDurationSeconds: TimeInterval?
    ) -> Double {
        guard
            let expectedDurationSeconds,
            expectedDurationSeconds > 0,
            totalWordCount > 0
        else {
            return configuration.wordsPerSecond
        }

        let derivedWordsPerSecond = Double(totalWordCount) / expectedDurationSeconds
        return max(0.1, derivedWordsPerSecond)
    }
}
