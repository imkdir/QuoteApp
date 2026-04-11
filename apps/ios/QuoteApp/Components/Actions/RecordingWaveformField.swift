import SwiftUI

struct RecordingWaveformField: View {
    let isRecording: Bool
    let levels: [CGFloat]

    private let fallbackLevels: [CGFloat] = [0.08, 0.12, 0.18, 0.28, 0.42, 0.33, 0.24, 0.18, 0.13, 0.1, 0.18, 0.24, 0.34, 0.26, 0.16, 0.1]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                let shapedLevel = pow(level, 0.9)
                Capsule(style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.8) : Color.secondary.opacity(0.7))
                    .frame(width: 3, height: 7 + (shapedLevel * 24))
                    .opacity(isRecording ? 0.35 + (Double(shapedLevel) * 0.6) : 0.45)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.06), value: displayLevels)
    }

    private var displayLevels: [CGFloat] {
        if levels.isEmpty {
            return fallbackLevels
        }

        return levels.map { level in
            let clamped = min(1.0, max(0.0, level))
            let curved = pow(clamped, 0.8)
            return isRecording ? max(0.03, curved) : max(0.05, curved)
        }
    }
}

#if DEBUG
struct RecordingWaveformField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecordingWaveformField(
                isRecording: true,
                levels: [0.08, 0.12, 0.2, 0.35, 0.48, 0.62, 0.55, 0.4, 0.3, 0.22, 0.18, 0.14, 0.26, 0.34, 0.22, 0.12]
            )
                .padding()
                .previewDisplayName("Recording")

            RecordingWaveformField(
                isRecording: false,
                levels: [0.08, 0.1, 0.12, 0.14, 0.12, 0.1, 0.08, 0.12, 0.16, 0.18, 0.16, 0.12, 0.1, 0.08, 0.1, 0.12]
            )
                .padding()
                .previewDisplayName("Stopped")
        }
    }
}
#endif
