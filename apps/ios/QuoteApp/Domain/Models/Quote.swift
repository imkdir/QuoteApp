import Foundation

struct Quote: Identifiable, Hashable, Decodable {
    let id: String
    let text: String

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
        let normalizedLineEndings = text
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
