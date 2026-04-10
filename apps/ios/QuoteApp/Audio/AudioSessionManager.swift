import AVFAudio
import Foundation

@MainActor
final class AudioSessionManager {
    enum MicrophonePermission: Equatable {
        case undetermined
        case denied
        case granted
    }

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

    var microphonePermission: MicrophonePermission {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }

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
        switch microphonePermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
