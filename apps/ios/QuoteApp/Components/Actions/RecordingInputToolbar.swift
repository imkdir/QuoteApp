import SwiftUI

struct RecordingInputToolbar: View {
    let state: RecordingInputToolbarState
    let waveformLevels: [CGFloat]
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RecordingWaveformField(
                isRecording: state == .recording,
                levels: waveformLevels
            )

            Button(action: trailingAction) {
                Image(systemName: state.trailingIconName)
                    .font(.title3.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state == .recording ? Color.red : Color.primary)
            .accessibilityLabel(state.trailingLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 48, maxHeight: 48)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func trailingAction() {
        switch state {
        case .recording:
            onStop()
        case .stopped:
            onClose()
        }
    }
}

#if DEBUG
struct RecordingInputToolbar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecordingInputToolbar(
                state: .recording,
                waveformLevels: [0.12, 0.22, 0.32, 0.48, 0.6, 0.44, 0.3, 0.22, 0.18, 0.12, 0.28, 0.4, 0.52, 0.36, 0.24, 0.14],
                onStop: {},
                onClose: {}
            )
                .padding()
                .previewDisplayName("Recording Toolbar")

            RecordingInputToolbar(state: .stopped, waveformLevels: [0.12, 0.18, 0.22, 0.3, 0.45, 0.32, 0.24, 0.18, 0.14, 0.12, 0.16, 0.2, 0.28, 0.22, 0.15, 0.12], onStop: {}, onClose: {})
                .padding()
                .previewDisplayName("Stopped Toolbar")
        }
    }
}
#endif
