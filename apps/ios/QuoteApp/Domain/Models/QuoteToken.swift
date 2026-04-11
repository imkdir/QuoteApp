import Foundation

struct QuoteToken: Identifiable, Hashable {
    let index: Int
    let lineIndex: Int
    let rawText: String
    let normalizedText: String
    let isSpoken: Bool
    let isMarked: Bool

    var id: Int { index }
}
