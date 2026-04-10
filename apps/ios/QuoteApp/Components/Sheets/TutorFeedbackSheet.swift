import SwiftUI

struct TutorFeedbackSheet: View {
    let analysis: PracticeAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titleText)
                .font(.title3.weight(.semibold))

            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)

            if analysis.state == .info, !analysis.markedNormalizedTokens.isEmpty {
                Divider()

                Text("Words to retry")
                    .font(.subheadline.weight(.semibold))

                Text(analysis.markedNormalizedTokens.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var titleText: String {
        switch analysis.state {
        case .info:
            return "Keep going"
        case .perfect:
            return "Great job"
        case .unavailable:
            return "Review unavailable"
        case .loading:
            return "Still reviewing"
        }
    }

    private var bodyText: String {
        if let feedbackText = analysis.feedbackText {
            return feedbackText
        }

        switch analysis.state {
        case .info:
            return "A few words need another try."
        case .perfect:
            return "You delivered this quote clearly and naturally."
        case .unavailable:
            return "We could not complete review for this attempt."
        case .loading:
            return "Reviewing your latest attempt."
        }
    }
}

#if DEBUG
struct TutorFeedbackSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TutorFeedbackSheet(
                analysis: PracticeAnalysis(
                    state: .info,
                    markedNormalizedTokens: ["boats", "ceaselessly", "past"],
                    feedbackText: "Watch stress on key nouns and keep your pacing steady."
                )
            )
            .previewDisplayName("Info")

            TutorFeedbackSheet(
                analysis: PracticeAnalysis(
                    state: .perfect,
                    feedbackText: "Excellent rhythm and pronunciation."
                )
            )
            .previewDisplayName("Perfect")

            TutorFeedbackSheet(
                analysis: PracticeAnalysis(
                    state: .unavailable,
                    feedbackText: "The review could not be completed for this attempt."
                )
            )
            .previewDisplayName("Unavailable")
        }
    }
}
#endif
