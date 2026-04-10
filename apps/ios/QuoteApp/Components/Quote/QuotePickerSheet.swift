import SwiftUI

struct QuotePickerSheet: View {
    let quotes: [Quote]
    let onSelect: (Quote) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Quotes")
                    .font(.headline)

                Spacer()

                Color.clear
                    .frame(width: 32, height: 32)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(quotes) { quote in
                        Button(action: { onSelect(quote) }) {
                            QuoteListItemView(quote: quote)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
    }
}

#if DEBUG
struct QuotePickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        QuotePickerSheet(
            quotes: MockQuotes.all,
            onSelect: { _ in },
            onClose: {}
        )
        .previewDisplayName("Quote Picker Sheet")
    }
}
#endif
