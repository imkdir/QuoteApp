import AVFAudio
import CoreGraphics
import Foundation

@MainActor
final class UserRecordingManager: NSObject, ObservableObject {
    enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case failedToPrepareRecorder
        case failedToStartRecorder
        case noActiveRecording

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required to record."
            case .failedToPrepareRecorder:
                return "Could not prepare recorder."
            case .failedToStartRecorder:
                return "Could not start recording."
            case .noActiveRecording:
                return "No active recording to stop."
            }
        }
    }

    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var meterLevels: [CGFloat]
    @Published private(set) var lastErrorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private static let meterBarCount = 16
    private static let defaultMeterLevels = Array(repeating: CGFloat(0.12), count: meterBarCount)

    override init() {
        self.meterLevels = UserRecordingManager.defaultMeterLevels
        super.init()
    }

    deinit {
        meterTimer?.invalidate()
    }

    func startRecording(audioSessionManager: AudioSessionManager?) async throws -> URL {
        if case .stopped = recordingState {
            clearRecording()
        }

        let permissionGranted: Bool
        if let audioSessionManager {
            permissionGranted = await audioSessionManager.requestMicrophonePermission()
        } else {
            permissionGranted = await AVAudioSession.sharedInstance().requestPermissionFallback()
        }

        guard permissionGranted else {
            lastErrorMessage = RecordingError.microphonePermissionDenied.localizedDescription
            throw RecordingError.microphonePermissionDenied
        }

        do {
            try audioSessionManager?.configureForVoiceInteraction()
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }

        let fileURL = makeDraftURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw RecordingError.failedToStartRecorder
            }

            audioRecorder = recorder
            recordingState = .recording(fileURL: fileURL)
            meterLevels = Self.defaultMeterLevels
            lastErrorMessage = nil
            startMetering()
            return fileURL
        } catch {
            lastErrorMessage = RecordingError.failedToPrepareRecorder.localizedDescription
            throw RecordingError.failedToPrepareRecorder
        }
    }

    func stopRecording() throws -> URL {
        guard let recorder = audioRecorder,
              recorder.isRecording else {
            throw RecordingError.noActiveRecording
        }

        recorder.stop()
        stopMetering()

        let fileURL = recorder.url
        audioRecorder = nil
        recordingState = .stopped(fileURL: fileURL)
        return fileURL
    }

    func clearRecording() {
        stopMetering()

        if let recorder = audioRecorder,
           recorder.isRecording {
            recorder.stop()
        }

        if let fileURL = recordingState.fileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        audioRecorder = nil
        recordingState = .idle
        meterLevels = Self.defaultMeterLevels
        lastErrorMessage = nil
    }

    private func startMetering() {
        stopMetering()

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureMeterLevel()
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func captureMeterLevel() {
        guard let recorder = audioRecorder else {
            return
        }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalized = max(CGFloat(0.04), min(CGFloat(1.0), CGFloat(pow(10.0, averagePower / 20.0))))
        meterLevels.append(normalized)

        if meterLevels.count > Self.meterBarCount {
            meterLevels.removeFirst(meterLevels.count - Self.meterBarCount)
        }
    }

    private func makeDraftURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quoteapp-draft-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}

extension UserRecordingManager: AVAudioRecorderDelegate {}

private extension AVAudioSession {
    func requestPermissionFallback() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
