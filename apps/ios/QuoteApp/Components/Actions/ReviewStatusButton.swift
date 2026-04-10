import SwiftUI

struct ReviewStatusButton: View {
    enum State: Equatable {
        case review
        case reviewing
        case reviewedInfo
        case reviewedPerfect
        case unavailable

        var title: String {
            switch self {
            case .review:
                return "Review"
            case .reviewing:
                return "Reviewing"
            case .reviewedInfo:
                return "Reviewed"
            case .reviewedPerfect:
                return "Reviewed"
            case .unavailable:
                return "Unavailable"
            }
        }

        var systemImage: String {
            switch self {
            case .review, .reviewing:
                return "arrow.down.message.fill"
            case .reviewedInfo:
                return "ellipsis.message.fill"
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
        Button(action: action) {
            Image(systemName: state.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.gray.opacity(0.2))
        .foregroundStyle(iconForegroundColor)
        .disabled(!state.isTappable)
        .accessibilityLabel(state.title)
    }

    private var iconForegroundColor: Color {
        switch state {
        case .unavailable:
            return .orange
        case .reviewedPerfect:
            return .green
        default:
            return .blue
        }
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
