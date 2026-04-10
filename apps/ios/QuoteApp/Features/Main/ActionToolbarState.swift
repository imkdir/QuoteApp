import Foundation

enum ActionToolbarState: Equatable {
    case `default`
    case speaking
    case pausedOrFinished
    case recording
    case recordedReadyToSend
    case reviewing
    case reviewedInfo
    case reviewedPerfect
    case unavailable

    var playbackMode: PlaybackActionButton.Mode? {
        switch self {
        case .speaking:
            return .pause
        case .default, .pausedOrFinished, .reviewedInfo, .reviewedPerfect, .unavailable:
            return .repeat
        case .recording, .recordedReadyToSend, .reviewing:
            return nil
        }
    }

    var reviewState: ReviewStatusButton.State {
        switch self {
        case .reviewing:
            return .reviewing
        case .reviewedInfo:
            return .reviewedInfo
        case .reviewedPerfect:
            return .reviewedPerfect
        case .unavailable:
            return .unavailable
        default:
            return .review
        }
    }

    var showsReviewButton: Bool {
        switch self {
        case .recording, .recordedReadyToSend:
            return false
        default:
            return true
        }
    }

    var showsRecordingToolbar: Bool {
        switch self {
        case .recording, .recordedReadyToSend:
            return true
        default:
            return false
        }
    }

    var showsRecordButton: Bool {
        switch self {
        case .recording, .recordedReadyToSend, .reviewing, .speaking:
            return false
        default:
            return true
        }
    }

    var showsSendButton: Bool {
        self == .recordedReadyToSend
    }
}
