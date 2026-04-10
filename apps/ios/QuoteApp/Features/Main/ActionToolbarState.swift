import Foundation

enum TutorPlaybackState: Equatable {
    case speaking
    case pausedOrFinished
}

enum LatestAttemptReviewState: Equatable {
    case none
    case loading
    case info
    case perfect
    case unavailable
}

struct ActionToolbarState: Equatable {
    let tutorPlaybackState: TutorPlaybackState
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

        switch tutorPlaybackState {
        case .speaking:
            return .pause
        case .pausedOrFinished:
            return .repeat
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
