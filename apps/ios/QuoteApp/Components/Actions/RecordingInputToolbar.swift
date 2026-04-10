import SwiftUI

struct RecordingInputToolbar: View {
    let state: RecordingInputToolbarState
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RecordingWaveformField(isRecording: state == .recording)

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
        .padding(.vertical, 4)
        .frame(minHeight: 44, maxHeight: 44)
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
            RecordingInputToolbar(state: .recording, onStop: {}, onClose: {})
                .padding()
                .previewDisplayName("Recording Toolbar")

            RecordingInputToolbar(state: .stopped, onStop: {}, onClose: {})
                .padding()
                .previewDisplayName("Stopped Toolbar")
        }
    }
}
#endif
