import SwiftUI

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.subheadline)
            Text("QuoteApp")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.0)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct BrandHeader_Previews: PreviewProvider {
    static var previews: some View {
        BrandHeader()
            .padding()
    }
}
#endif
