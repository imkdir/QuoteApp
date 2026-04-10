import SwiftUI

struct StartView: View {
    let onPickQuote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandHeader()

            Spacer(minLength: 20)

            Text("Let’s speak")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Choose a quote and begin a simple speaking practice round.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button(action: onPickQuote) {
                Label("Choose a quote", systemImage: "text.quote")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView(onPickQuote: {})
            .padding(24)
            .previewDisplayName("Start State")
    }
}
#endif
