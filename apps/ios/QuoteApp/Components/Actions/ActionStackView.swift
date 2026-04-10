import SwiftUI

struct ActionStackView: View {
    let toolbarState: ActionToolbarState
    let onPlaybackTapped: () -> Void
    let onRecordTapped: () -> Void
    let onStopRecordingTapped: () -> Void
    let onCloseRecordingTapped: () -> Void
    let onSendTapped: () -> Void
    let onReviewTapped: () -> Void

    var body: some View {
        Group {
            if toolbarState.showsRecordingToolbar {
                recordingFlowLayout
            } else {
                standardLayout
            }
        }
    }

    private var standardLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            if let playbackMode = toolbarState.playbackMode {
                PlaybackActionButton(mode: playbackMode, action: onPlaybackTapped)
            }

            if toolbarState.showsRecordButton {
                recordButton
            }

            if toolbarState.showsReviewButton {
                analysisGroup
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.15), value: toolbarState)
    }

    private var recordingFlowLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            RecordingInputToolbar(
                state: toolbarState.recordingToolbarState,
                onStop: onStopRecordingTapped,
                onClose: onCloseRecordingTapped
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if toolbarState.showsSendButton {
                sendButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: toolbarState)
    }

    @ViewBuilder
    private var analysisGroup: some View {
        if let reviewState = toolbarState.reviewState {
            ReviewStatusButton(state: reviewState, action: onReviewTapped)
        }
    }

    private var recordButton: some View {
        Button(action: onRecordTapped) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Record")
    }

    private var sendButton: some View {
        Button(action: onSendTapped) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .accessibilityLabel("Send")
    }
}

#if DEBUG
struct ActionStackView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .speaking,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .none,
                    hasAttemptHistory: false
                ),
                title: "Speaking (No Attempts)"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .speaking,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Speaking (With History)"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: .recording,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Recording Draft"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: .stopped,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Send Ready Draft"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .loading,
                    hasAttemptHistory: true
                ),
                title: "Latest Loading"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Latest Info"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .perfect,
                    hasAttemptHistory: true
                ),
                title: "Latest Perfect"
            )
            preview(
                toolbarState: ActionToolbarState(
                    tutorPlaybackState: .pausedOrFinished,
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .unavailable,
                    hasAttemptHistory: true
                ),
                title: "Latest Unavailable"
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }

    private static func preview(
        toolbarState: ActionToolbarState,
        title: String
    ) -> some View {
        ActionStackView(
            toolbarState: toolbarState,
            onPlaybackTapped: {},
            onRecordTapped: {},
            onStopRecordingTapped: {},
            onCloseRecordingTapped: {},
            onSendTapped: {},
            onReviewTapped: {}
        )
        .previewDisplayName(title)
    }
}
#endif
