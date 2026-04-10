import SwiftUI

struct QuoteListItemView: View {
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.previewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("\(quote.bookTitle) • \(quote.author)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if DEBUG
struct QuoteListItemView_Previews: PreviewProvider {
    static var previews: some View {
        QuoteListItemView(quote: MockQuotes.all[0])
            .padding()
    }
}
#endif
