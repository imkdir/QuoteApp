import SwiftUI

struct PlaybackActionButton: View {
    enum Mode: Equatable {
        case pause
        case play
        case repeatPlayback

        var title: String {
            switch self {
            case .pause:
                return "Pause"
            case .play:
                return "Play"
            case .repeatPlayback:
                return "Repeat"
            }
        }

        var systemImage: String {
            switch self {
            case .pause:
                return "pause.circle.fill"
            case .play, .repeatPlayback:
                return "play.circle.fill"
            }
        }

        var accessibilityHint: String {
            switch self {
            case .pause:
                return "Pauses tutor playback"
            case .play:
                return "Starts tutor playback"
            case .repeatPlayback:
                return "Restarts tutor playback from the beginning"
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
        .accessibilityHint(mode.accessibilityHint)
    }
}

#if DEBUG
struct PlaybackActionButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PlaybackActionButton(mode: .pause, action: {})
                .padding()
                .previewDisplayName("Pause")

            PlaybackActionButton(mode: .play, action: {})
                .padding()
                .previewDisplayName("Play")

            PlaybackActionButton(mode: .repeatPlayback, action: {})
                .padding()
                .previewDisplayName("Repeat")
        }
    }
}
#endif
