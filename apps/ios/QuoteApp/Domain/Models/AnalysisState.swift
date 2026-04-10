import Foundation

enum AnalysisState: String, Codable, CaseIterable, Hashable {
    case loading
    case info
    case perfect
    case unavailable

    init(backendValue: String) {
        self = AnalysisState(rawValue: backendValue) ?? .unavailable
    }
}
