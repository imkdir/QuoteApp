import SwiftUI

struct RecordingWaveformField: View {
    let isRecording: Bool

    private let sampleLevels: [CGFloat] = [0.25, 0.5, 0.35, 0.7, 0.4, 0.6, 0.3, 0.55, 0.38, 0.48]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(sampleLevels.enumerated()), id: \.offset) { index, level in
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
    }
}

#if DEBUG
struct RecordingWaveformField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecordingWaveformField(isRecording: true)
                .padding()
                .previewDisplayName("Recording")

            RecordingWaveformField(isRecording: false)
                .padding()
                .previewDisplayName("Stopped")
        }
    }
}
#endif
