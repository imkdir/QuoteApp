import SwiftUI

struct StartView: View {
    let onPickQuote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandHeader()

            Spacer()
                .frame(height: 100)

            Text("Let’s practice")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Button(action: onPickQuote) {
                Label("Choose a quote", systemImage: "text.quote")
                    .font(.headline)
                    .padding(4)
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
