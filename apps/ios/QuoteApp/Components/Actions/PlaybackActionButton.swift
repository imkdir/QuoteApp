import SwiftUI

struct PlaybackActionButton: View {
    enum Mode: Equatable {
        case pause
        case playRepeat

        var title: String {
            switch self {
            case .pause:
                return "Pause"
            case .playRepeat:
                return "Play"
            }
        }

        var systemImage: String {
            switch self {
            case .pause:
                return "pause.circle.fill"
            case .playRepeat:
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
        .accessibilityHint(mode == .pause ? "Pauses tutor playback" : "Starts, resumes, or repeats tutor playback")
    }
}

#if DEBUG
struct PlaybackActionButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PlaybackActionButton(mode: .pause, action: {})
                .padding()
                .previewDisplayName("Pause")

            PlaybackActionButton(mode: .playRepeat, action: {})
                .padding()
                .previewDisplayName("Play/Repeat")
        }
    }
}
#endif
