import AVFAudio
import Foundation

@MainActor
final class AudioSessionManager {
    enum AudioSessionError: LocalizedError {
        case setupFailed(String)

        var errorDescription: String? {
            switch self {
            case let .setupFailed(message):
                return message
            }
        }
    }

    enum AudioSessionState: Equatable {
        case idle
        case configured
        case failed(message: String)
    }

    private(set) var state: AudioSessionState = .idle

    func configureForVoiceInteraction() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
            state = .configured
        } catch {
            let message = "Could not configure audio session for voice interaction."
            state = .failed(message: message)
            throw AudioSessionError.setupFailed(message)
        }
    }

    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        state = .idle
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
