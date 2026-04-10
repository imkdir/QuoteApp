import Foundation

struct PracticeAnalysis: Identifiable, Hashable {
    let id: UUID
    let state: AnalysisState
    let markedNormalizedTokens: [String]
    let feedbackText: String?

    init(
        id: UUID = UUID(),
        state: AnalysisState,
        markedNormalizedTokens: [String] = [],
        feedbackText: String? = nil
    ) {
        self.id = id
        self.state = state
        self.markedNormalizedTokens = markedNormalizedTokens
        self.feedbackText = feedbackText
    }
}
