import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(fileURL: URL)
    case stopped(fileURL: URL)

    var fileURL: URL? {
        switch self {
        case .idle:
            return nil
        case let .recording(fileURL), let .stopped(fileURL):
            return fileURL
        }
    }
}
