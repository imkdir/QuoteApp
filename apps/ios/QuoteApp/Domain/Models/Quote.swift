import Foundation

struct Quote: Identifiable, Hashable, Decodable {
    let id: String
    let previewText: String
    let fullText: String
    let bookTitle: String
    let author: String
    let mockMarkedNormalizedTokens: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case preview
        case text
        case previewText
        case fullText
        case bookTitle
        case author
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let previewText =
            try container.decodeIfPresent(String.self, forKey: .preview) ??
            container.decode(String.self, forKey: .previewText)

        let fullText =
            try container.decodeIfPresent(String.self, forKey: .text) ??
            container.decode(String.self, forKey: .fullText)

        self.id = try container.decode(String.self, forKey: .id)
        self.previewText = previewText
        self.fullText = fullText
        self.bookTitle = try container.decodeIfPresent(String.self, forKey: .bookTitle) ?? ""
        self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        self.mockMarkedNormalizedTokens = []
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
