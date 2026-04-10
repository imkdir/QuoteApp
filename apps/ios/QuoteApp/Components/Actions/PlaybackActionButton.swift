import SwiftUI

struct PlaybackActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

#if DEBUG
struct PlaybackActionButton_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackActionButton(title: "Repeat", action: {})
            .padding()
    }
}
#endif
