import SwiftUI

struct ActionStackView: View {
    let onRepeat: () -> Void
    let onRecord: () -> Void
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PlaybackActionButton(title: "Repeat", action: onRepeat)

            Button(action: onRecord) {
                Label("Record", systemImage: "waveform.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            ReviewStatusButton(title: "Review", systemImage: "arrow.down.message.fill", action: onReview)
        }
    }
}

#if DEBUG
struct ActionStackView_Previews: PreviewProvider {
    static var previews: some View {
        ActionStackView(onRepeat: {}, onRecord: {}, onReview: {})
            .padding()
    }
}
#endif
