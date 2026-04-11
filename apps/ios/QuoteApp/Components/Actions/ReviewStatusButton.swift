import SwiftUI

struct ReviewStatusButton: View {
    enum State: Equatable {
        case reviewing
        case reviewedInfo
        case reviewedPerfect
        case unavailable

        var title: String {
            switch self {
            case .reviewing:
                return "Reviewing"
            case .reviewedInfo:
                return "Reviewed Info"
            case .reviewedPerfect:
                return "Reviewed Perfect"
            case .unavailable:
                return "Unavailable"
            }
        }

        var systemImage: String {
            switch self {
            case .reviewing:
                return "ellipsis.message.fill"
            case .reviewedInfo:
                return "message.badge.filled.fill"
            case .reviewedPerfect:
                return "checkmark.message.fill"
            case .unavailable:
                return "exclamationmark.message.fill"
            }
        }

        var isTappable: Bool {
            switch self {
            case .reviewing:
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
        .buttonStyle(.borderedProminent)
        .tint(.gray.opacity(state == .reviewing ? 0.15 : 0.2))
        .foregroundStyle(iconForegroundColor)
        .opacity(state == .reviewing ? 0.72 : 1.0)
        .disabled(!state.isTappable)
        .accessibilityLabel(state.title)
        .accessibilityHint(accessibilityHint)
    }

    private var iconForegroundColor: Color {
        switch state {
        case .unavailable:
            return .orange
        case .reviewedPerfect:
            return .green
        case .reviewing:
            return .secondary
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
