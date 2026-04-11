import SwiftUI

struct ActionStackView: View {
    let toolbarState: ActionToolbarState
    let recordingWaveformLevels: [CGFloat]
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
                waveformLevels: recordingWaveformLevels,
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
                    playbackState: .playing(
                        progress: PlaybackProgress(spokenWordCount: 7, totalWordCount: 24)
                    ),
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .none,
                    hasAttemptHistory: false
                ),
                title: "Speaking (No Attempts)"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .playing(
                        progress: PlaybackProgress(spokenWordCount: 10, totalWordCount: 24)
                    ),
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Speaking (With History)"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .paused(
                        progress: PlaybackProgress(spokenWordCount: 9, totalWordCount: 24)
                    ),
                    localRecordingDraftState: .recording,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Recording Draft"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .paused(
                        progress: PlaybackProgress(spokenWordCount: 9, totalWordCount: 24)
                    ),
                    localRecordingDraftState: .stopped,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Send Ready Draft"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .paused(
                        progress: PlaybackProgress(spokenWordCount: 8, totalWordCount: 24)
                    ),
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .loading,
                    hasAttemptHistory: true
                ),
                title: "Latest Loading"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .paused(
                        progress: PlaybackProgress(spokenWordCount: 12, totalWordCount: 24)
                    ),
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .info,
                    hasAttemptHistory: true
                ),
                title: "Latest Info"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .finishedAtEnd(
                        progress: PlaybackProgress(spokenWordCount: 24, totalWordCount: 24)
                    ),
                    localRecordingDraftState: nil,
                    latestAttemptReviewState: .perfect,
                    hasAttemptHistory: true
                ),
                title: "Latest Perfect"
            )
            preview(
                toolbarState: ActionToolbarState(
                    playbackState: .finishedAtEnd(
                        progress: PlaybackProgress(spokenWordCount: 24, totalWordCount: 24)
                    ),
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
            recordingWaveformLevels: [0.1, 0.15, 0.2, 0.35, 0.5, 0.3, 0.45, 0.22, 0.18, 0.12, 0.4, 0.55, 0.3, 0.2, 0.16, 0.12],
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
