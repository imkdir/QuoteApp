import SwiftUI

struct QuoteListView: View {
    let quotes: [Quote]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (Quote) -> Void
    let onRetry: () -> Void

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading quotes...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, quotes.isEmpty {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
    }
}

#if DEBUG
struct QuotePickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            QuoteListView(
                quotes: [],
                isLoading: true,
                errorMessage: nil,
                onSelect: { _ in },
                onRetry: {},
            )
            .previewDisplayName("Quote Picker Loading")

            QuoteListView(
                quotes: MockQuotes.all,
                isLoading: false,
                errorMessage: nil,
                onSelect: { _ in },
                onRetry: {},
            )
            .previewDisplayName("Quote Picker Success")

            QuoteListView(
                quotes: [],
                isLoading: false,
                errorMessage: "Could not load quotes. Check backend and retry.",
                onSelect: { _ in },
                onRetry: {},
            )
            .previewDisplayName("Quote Picker Failure")
        }
    }
}
#endif
