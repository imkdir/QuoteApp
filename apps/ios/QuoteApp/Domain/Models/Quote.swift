import Foundation

struct Quote: Identifiable, Hashable {
    let id: String
    let previewText: String
    let fullText: String
    let bookTitle: String
    let author: String
    let mockMarkedNormalizedTokens: [String]

    init(
        id: String,
        previewText: String,
        fullText: String,
        bookTitle: String,
        author: String,
        mockMarkedNormalizedTokens: [String] = []
    ) {
        self.id = id
        self.previewText = previewText
        self.fullText = fullText
        self.bookTitle = bookTitle
        self.author = author
        self.mockMarkedNormalizedTokens = mockMarkedNormalizedTokens
    }

    var wordCount: Int {
        fullText.split(whereSeparator: { $0.isWhitespace }).count
    }

    func makeTokens(spokenCount: Int, markedTokenIndexes: Set<Int>) -> [QuoteToken] {
        let rawTokens = fullText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let clampedSpokenCount = max(0, min(spokenCount, rawTokens.count))

        return rawTokens.enumerated().map { index, rawToken in
            QuoteToken(
                index: index,
                rawText: rawToken,
                normalizedText: normalize(rawToken),
                isSpoken: index < clampedSpokenCount,
                isMarked: markedTokenIndexes.contains(index)
            )
        }
    }

    private func normalize(_ token: String) -> String {
        token
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9']", with: "", options: .regularExpression)
    }
}
