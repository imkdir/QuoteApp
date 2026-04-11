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
    let hasAttemptHistory: Bool

    var isInRecordingExclusiveMode: Bool {
        localRecordingDraftState != nil
    }

    var playbackMode: PlaybackActionButton.Mode? {
        guard !isInRecordingExclusiveMode else {
            return nil
        }

        switch playbackState {
        case .playing:
            return .pause
        case .idle, .paused:
            return .play
        case .finishedAtEnd:
            return .repeatPlayback
        }
    }

    var reviewState: ReviewStatusButton.State? {
        guard !isInRecordingExclusiveMode else {
            return nil
        }

        guard hasAttemptHistory || latestAttemptReviewState == .loading else {
            return nil
        }

        switch latestAttemptReviewState {
        case .none:
            return .review
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

    var showsRecordButton: Bool {
        !isInRecordingExclusiveMode
    }

    var showsReviewButton: Bool {
        reviewState != nil
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
