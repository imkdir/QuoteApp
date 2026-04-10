import SwiftUI

struct QuoteTextView: View {
    let quote: Quote

    var body: some View {
        Text(quote.fullText)
            .font(.system(.title2, design: .serif))
            .lineSpacing(8)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

#if DEBUG
struct QuoteTextView_Previews: PreviewProvider {
    static var previews: some View {
        QuoteTextView(quote: MockQuotes.all[0])
            .padding()
            .previewDisplayName("Quote Text")
    }
}
#endif
