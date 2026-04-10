import Foundation

enum RecordingInputToolbarState: Equatable {
    case recording
    case stopped

    var trailingIconName: String {
        switch self {
        case .recording:
            return "stop.circle.fill"
        case .stopped:
            return "xmark.circle.fill"
        }
    }

    var trailingLabel: String {
        switch self {
        case .recording:
            return "Stop"
        case .stopped:
            return "Close"
        }
    }
}
