import Foundation

struct Quote: Identifiable, Hashable, Decodable {
    let id: String
    let previewText: String
    let fullText: String
    let bookTitle: String
    let author: String

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
        author: String
    ) {
        self.id = id
        self.previewText = previewText
        self.fullText = fullText
        self.bookTitle = bookTitle
        self.author = author
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
    }

    var wordCount: Int {
        tokenizedWordsByLine().reduce(into: 0) { partialResult, lineWords in
            partialResult += lineWords.count
        }
    }

    func makeTokens(spokenCount: Int, markedTokenIndexes: Set<Int>) -> [QuoteToken] {
        let wordsByLine = tokenizedWordsByLine()
        let totalTokenCount = wordsByLine.reduce(into: 0) { partialResult, lineWords in
            partialResult += lineWords.count
        }
        let clampedSpokenCount = max(0, min(spokenCount, totalTokenCount))

        var flattenedTokens: [QuoteToken] = []
        flattenedTokens.reserveCapacity(totalTokenCount)

        var globalIndex = 0
        for (lineIndex, lineWords) in wordsByLine.enumerated() {
            for rawToken in lineWords {
                flattenedTokens.append(
                    QuoteToken(
                        index: globalIndex,
                        lineIndex: lineIndex,
                        rawText: rawToken,
                        normalizedText: normalize(rawToken),
                        isSpoken: globalIndex < clampedSpokenCount,
                        isMarked: markedTokenIndexes.contains(globalIndex)
                    )
                )
                globalIndex += 1
            }
        }

        return flattenedTokens
    }

    private func normalize(_ token: String) -> String {
        token
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9']", with: "", options: .regularExpression)
    }

    private func tokenizedWordsByLine() -> [[String]] {
        let normalizedLineEndings = fullText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedLineEndings.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        return lines.map { line in
            line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
    }
}
