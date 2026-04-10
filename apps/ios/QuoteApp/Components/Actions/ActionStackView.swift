import SwiftUI

struct ActionStackView: View {
    let toolbarState: ActionToolbarState
    let recordingToolbarState: RecordingInputToolbarState
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
    }

    private var recordingFlowLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            RecordingInputToolbar(
                state: recordingToolbarState,
                onStop: onStopRecordingTapped,
                onClose: onCloseRecordingTapped
            )
            .frame(maxWidth: .infinity)

            if toolbarState.showsSendButton {
                sendButton
            }
        }
    }

    private var analysisGroup: some View {
        ReviewStatusButton(state: toolbarState.reviewState, action: onReviewTapped)
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
            preview(for: .speaking, recordingState: .recording, title: "Speaking")
            preview(for: .pausedOrFinished, recordingState: .recording, title: "Paused or Finished")
            preview(for: .recording, recordingState: .recording, title: "Recording")
            preview(for: .recordedReadyToSend, recordingState: .stopped, title: "Stopped Send-Ready")
            preview(for: .reviewing, recordingState: .recording, title: "Reviewing")
            preview(for: .reviewedInfo, recordingState: .recording, title: "Reviewed Info")
            preview(for: .reviewedPerfect, recordingState: .recording, title: "Reviewed Perfect")
            preview(for: .unavailable, recordingState: .recording, title: "Unavailable")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }

    private static func preview(
        for state: ActionToolbarState,
        recordingState: RecordingInputToolbarState,
        title: String
    ) -> some View {
        ActionStackView(
            toolbarState: state,
            recordingToolbarState: recordingState,
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
