import SwiftUI

struct PlaybackActionButton: View {
    enum Mode: Equatable {
        case pause
        case `repeat`

        var title: String {
            switch self {
            case .pause:
                return "Pause"
            case .repeat:
                return "Repeat"
            }
        }

        var systemImage: String {
            switch self {
            case .pause:
                return "pause.circle.fill"
            case .repeat:
                return "play.circle.fill"
            }
        }
    }

    let mode: Mode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.gray.opacity(0.2))
        .foregroundStyle(.blue)
        .accessibilityLabel(mode.title)
    }
}

#if DEBUG
struct PlaybackActionButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PlaybackActionButton(mode: .pause, action: {})
                .padding()
                .previewDisplayName("Pause")

            PlaybackActionButton(mode: .repeat, action: {})
                .padding()
                .previewDisplayName("Repeat")
        }
    }
}
#endif
