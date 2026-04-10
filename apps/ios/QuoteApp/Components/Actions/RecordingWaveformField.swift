import SwiftUI

struct RecordingWaveformField: View {
    let isRecording: Bool
    let levels: [CGFloat]

    private let fallbackLevels: [CGFloat] = [0.12, 0.16, 0.2, 0.34, 0.52, 0.38, 0.27, 0.2, 0.14, 0.12, 0.2, 0.26, 0.4, 0.3, 0.18, 0.12]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(displayLevels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.8) : Color.secondary.opacity(0.7))
                    .frame(width: 3, height: 8 + (level * 18))
                    .opacity(isRecording ? 0.6 + (Double(index % 3) * 0.15) : 0.45)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.linear(duration: 0.08), value: displayLevels)
    }

    private var displayLevels: [CGFloat] {
        if levels.isEmpty {
            return fallbackLevels
        }

        return levels.map { min(1.0, max(0.05, $0)) }
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
