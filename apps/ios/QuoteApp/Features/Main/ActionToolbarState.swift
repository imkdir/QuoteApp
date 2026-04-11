import Foundation

enum LatestAttemptReviewState: Equatable {
    case none
    case loading
    case info
    case perfect
    case unavailable
}

struct ActionToolbarState: Equatable {
    let playbackState: PlaybackState
    let localRecordingDraftState: LocalRecordingDraftState?
    let latestAttemptReviewState: LatestAttemptReviewState
    let hasVisibleReviewState: Bool

    var isInRecordingExclusiveMode: Bool {
        localRecordingDraftState != nil
    }

    var playbackMode: PlaybackActionButton.Mode {
        switch playbackState {
        case .playing:
            return .pause
        case .idle:
            return .play
        case let .requesting(_, origin):
            switch origin {
            case .play:
                return .play
            case .repeatPlayback:
                return .repeatPlayback
            }
        case .paused:
            return .play
        case .finishedAtEnd:
            return .repeatPlayback
        }
    }

    var reviewState: ReviewStatusButton.State {
        guard !isInRecordingExclusiveMode else {
            return .reviewedNone
        }

        guard hasVisibleReviewState else {
            return .reviewedNone
        }

        switch latestAttemptReviewState {
        case .none:
            return .reviewedNone
        case .loading:
            return .reviewing
        case .info:
            return .reviewedInfo
        case .perfect:
            return .reviewedPerfect
        case .unavailable:
            return .unavailable
        }
    }

    var showsRecordingToolbar: Bool {
        isInRecordingExclusiveMode
    }

    var showsSendButton: Bool {
        localRecordingDraftState == .stopped
    }

    var recordingToolbarState: RecordingInputToolbarState {
        switch localRecordingDraftState {
        case .stopped:
            return .stopped
        default:
            return .recording
        }
    }
}
