import Foundation

enum AnalysisState: String, Codable, CaseIterable, Hashable {
    case loading
    case info
    case perfect
    case unavailable
}
