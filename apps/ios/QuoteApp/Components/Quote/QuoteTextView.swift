import SwiftUI

struct QuoteTextView: View {
    let tokens: [QuoteToken]

    var body: some View {
        Group {
            if tokens.isEmpty {
                Text("No quote selected.")
                    .foregroundStyle(.secondary)
            } else {
                styledQuoteText
            }
        }
        .font(.system(.title2, design: .serif))
        .lineSpacing(8)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.14), value: spokenWordCount)
        .animation(.easeInOut(duration: 0.18), value: markedWordCount)
    }

    private var styledQuoteText: Text {
        tokens.enumerated().reduce(Text("")) { partialResult, pair in
            let index = pair.offset
            let token = pair.element
            let tokenText = styledText(for: token)
            let prefixText = separatorTextBeforeToken(at: index)
            return partialResult + prefixText + tokenText
        }
    }

    private func styledText(for token: QuoteToken) -> Text {
        let foregroundColor = token.isSpoken ? Color.primary : Color.secondary.opacity(0.45)
        let underlineColor = token.isMarked ? Color.primary : Color.clear

        return Text(token.rawText)
            .foregroundColor(foregroundColor)
            .underline(token.isMarked, color: underlineColor)
    }

    private var spokenWordCount: Int {
        tokens.filter { $0.isSpoken }.count
    }

    private var markedWordCount: Int {
        tokens.filter { $0.isMarked }.count
    }

    private func separatorTextBeforeToken(at index: Int) -> Text {
        guard index > 0 else {
            let leadingLineBreaks = max(0, tokens[index].lineIndex)
            if leadingLineBreaks == 0 {
                return Text("")
            }
            return Text(String(repeating: "\n", count: leadingLineBreaks))
        }

        let previousToken = tokens[index - 1]
        let currentToken = tokens[index]
        let lineAdvance = currentToken.lineIndex - previousToken.lineIndex

        if lineAdvance > 0 {
            return Text(String(repeating: "\n", count: lineAdvance))
        }
        return Text(" ")
    }
}

#if DEBUG
struct QuoteTextView_Previews: PreviewProvider {
    private static let quote = MockQuotes.all[0]

    static var previews: some View {
        Group {
            QuoteTextView(tokens: quote.makeTokens(spokenCount: 0, markedTokenIndexes: []))
                .padding()
                .previewDisplayName("All Dimmed")

            QuoteTextView(tokens: quote.makeTokens(spokenCount: 6, markedTokenIndexes: []))
                .padding()
                .previewDisplayName("Partially Spoken")

            QuoteTextView(tokens: quote.makeTokens(spokenCount: 6, markedTokenIndexes: [4, 9, 13]))
                .padding()
                .previewDisplayName("Reviewed with Marked Words")
        }
    }
}
#endif
