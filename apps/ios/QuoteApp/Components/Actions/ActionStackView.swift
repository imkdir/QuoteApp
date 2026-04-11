import SwiftUI

struct ActionStackView: View {
    let toolbarState: ActionToolbarState
    let isPlaybackButtonDisabled: Bool
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
        Group {
            if let playbackMode = toolbarState.playbackMode {
                PlaybackActionButton(
                    mode: playbackMode,
                    isDisabled: isPlaybackButtonDisabled,
                    action: onPlaybackTapped
                )
            }

            if toolbarState.showsRecordButton {
                recordButton
            }

            if toolbarState.showsReviewButton {
                ReviewStatusButton(state: toolbarState.reviewState, action: onReviewTapped)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toolbarState)
    }

    private var recordingFlowLayout: some View {
        Group {
            RecordingInputToolbar(
                state: toolbarState.recordingToolbarState,
                waveformLevels: recordingWaveformLevels,
                onStop: onStopRecordingTapped,
                onClose: onCloseRecordingTapped
            )

            if toolbarState.showsSendButton {
                sendButton
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toolbarState)
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
                    hasVisibleReviewState: false
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
                    hasVisibleReviewState: true
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
            isPlaybackButtonDisabled: false,
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
