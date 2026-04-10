import SwiftUI

struct ReviewStatusButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

#if DEBUG
struct ReviewStatusButton_Previews: PreviewProvider {
    static var previews: some View {
        ReviewStatusButton(title: "Review", systemImage: "arrow.down.message.fill", action: {})
            .padding()
    }
}
#endif
