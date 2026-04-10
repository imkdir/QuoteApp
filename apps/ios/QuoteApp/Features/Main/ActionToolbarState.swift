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

    var playbackMode: PlaybackActionButton.Mode? {
        guard localRecordingDraftState == nil else {
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
        guard localRecordingDraftState == nil else {
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
        localRecordingDraftState != nil
    }

    var showsRecordButton: Bool {
        localRecordingDraftState == nil
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
