import Foundation

struct PlaybackProgress: Equatable {
    let spokenWordCount: Int
    let totalWordCount: Int

    init(spokenWordCount: Int, totalWordCount: Int) {
        let clampedTotal = max(0, totalWordCount)
        let clampedSpoken = min(max(0, spokenWordCount), clampedTotal)
        self.spokenWordCount = clampedSpoken
        self.totalWordCount = clampedTotal
    }

    var fractionComplete: Double {
        guard totalWordCount > 0 else {
            return 1
        }

        return Double(spokenWordCount) / Double(totalWordCount)
    }

    var isAtEnd: Bool {
        spokenWordCount >= totalWordCount
    }

    var withSpokenWordCountAtEnd: PlaybackProgress {
        PlaybackProgress(
            spokenWordCount: totalWordCount,
            totalWordCount: totalWordCount
        )
    }
}

enum PlaybackState: Equatable {
    case idle(totalWordCount: Int)
    case playing(progress: PlaybackProgress)
    case paused(progress: PlaybackProgress)
    case finishedAtEnd(progress: PlaybackProgress)

    var progress: PlaybackProgress {
        switch self {
        case let .idle(totalWordCount):
            return PlaybackProgress(spokenWordCount: 0, totalWordCount: totalWordCount)
        case let .playing(progress), let .paused(progress), let .finishedAtEnd(progress):
            return progress
        }
    }

    var spokenWordCount: Int {
        progress.spokenWordCount
    }

    var totalWordCount: Int {
        progress.totalWordCount
    }

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }

    var isFinishedAtEnd: Bool {
        if case .finishedAtEnd = self {
            return true
        }
        return false
    }
}
