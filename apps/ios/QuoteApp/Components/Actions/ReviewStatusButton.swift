import SwiftUI

struct ReviewStatusButton: View {
    enum State: Equatable {
        case reviewing
        case reviewedInfo
        case reviewedPerfect
        case reviewedNone
        case unavailable

        var title: String {
            switch self {
            case .reviewing:
                return "Reviewing"
            case .reviewedInfo:
                return "Reviewed"
            case .reviewedPerfect:
                return "Reviewed"
            case .unavailable:
                return "Review unavailable"
            case .reviewedNone:
                return "No review yet"
            }
        }

        var systemImage: String {
            switch self {
            case .reviewing:
                return "message.badge.waveform.fill"
            case .reviewedInfo:
                return "ellipsis.message.fill"
            case .reviewedPerfect:
                return "checkmark.message.fill"
            case .unavailable:
                return "exclamationmark.message.fill"
            case .reviewedNone:
                return "message.fill"
            }
        }

        var isTappable: Bool {
            switch self {
            case .reviewing, .reviewedNone:
                return false
            default:
                return true
            }
        }
    }

    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: state.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(iconForegroundColor)
        .disabled(!state.isTappable)
        .accessibilityLabel(state.title)
        .accessibilityHint(accessibilityHint)
    }

    private var iconForegroundColor: Color {
        switch state {
        case .reviewedPerfect:
            return .green
        case .reviewedNone:
            return Color(uiColor: .systemGray4)
        default:
            return .blue
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .reviewing:
            return "Review is in progress"
        case .reviewedInfo, .reviewedPerfect, .unavailable:
            return "Opens review details"
        case .reviewedNone:
            return "No review details are available yet"
        }
    }

    private func handleTap() {
        guard state.isTappable else {
            return
        }

        action()
    }
}

#if DEBUG
struct ReviewStatusButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ReviewStatusButton(state: .reviewing, action: {})
                .padding()
                .previewDisplayName("Reviewing")

            ReviewStatusButton(state: .reviewedInfo, action: {})
                .padding()
                .previewDisplayName("Reviewed Info")

            ReviewStatusButton(state: .reviewedPerfect, action: {})
                .padding()
                .previewDisplayName("Reviewed Perfect")

            ReviewStatusButton(state: .unavailable, action: {})
                .padding()
                .previewDisplayName("Unavailable")
        }
    }
}
#endif
