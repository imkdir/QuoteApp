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
    private(set) var lastConfigurationWarning: String?

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
        var warnings: [String] = []

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )

            // Route capabilities vary on physical devices (Bluetooth HFP, built-in mic, wired headsets).
            // Treat preference failures as non-fatal so recording can still start with route defaults.
            do {
                try session.setPreferredSampleRate(44_100)
            } catch {
                warnings.append("sample-rate preference not applied")
            }

            do {
                try session.setPreferredInputNumberOfChannels(1)
            } catch {
                warnings.append("input-channel preference not applied")
            }

            do {
                try session.setPreferredIOBufferDuration(0.01)
            } catch {
                warnings.append("io-buffer preference not applied")
            }

            try session.setActive(true)
            lastConfigurationWarning = warnings.isEmpty ? nil : warnings.joined(separator: "; ")
            state = .configured
        } catch {
            let message = "Could not configure audio session for voice interaction."
            state = .failed(message: message)
            lastConfigurationWarning = nil
            throw AudioSessionError.setupFailed(message)
        }
    }

    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        lastConfigurationWarning = nil
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
