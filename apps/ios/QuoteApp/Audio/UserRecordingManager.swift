import AVFAudio
import CoreGraphics
import Foundation

@MainActor
final class UserRecordingManager: NSObject, ObservableObject {
    enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case failedToPrepareRecorder(reason: String? = nil)
        case failedToStartRecorder(reason: String? = nil)
        case noActiveRecording

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required to record."
            case let .failedToPrepareRecorder(reason):
                return reason.map { "Could not prepare recorder: \($0)" } ?? "Could not prepare recorder."
            case let .failedToStartRecorder(reason):
                return reason.map { "Could not start recording: \($0)" } ?? "Could not start recording."
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
    private var smoothedMeterLevel: CGFloat = 0
    private static let meterBarCount = 16
    private static let meterSampleInterval: TimeInterval = 1.0 / 30.0
    private static let defaultMeterLevels = Array(repeating: CGFloat(0.08), count: meterBarCount)
    private static let minimumDisplayLevel: CGFloat = 0.03
    private static let averageFloorDecibels: Float = -52
    private static let peakFloorDecibels: Float = -38
    private static let normalizationGamma: CGFloat = 0.65
    private static let attackSmoothing: CGFloat = 0.5
    private static let releaseSmoothing: CGFloat = 0.22
    private static let noiseGateThreshold: CGFloat = 0.055
    private static let noiseGateAttenuation: CGFloat = 0.4

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
        let settings = makeRecorderSettings()

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else {
                throw RecordingError.failedToPrepareRecorder()
            }

            guard recorder.record() else {
                throw RecordingError.failedToStartRecorder()
            }

            audioRecorder = recorder
            recordingState = .recording(fileURL: fileURL)
            meterLevels = Self.defaultMeterLevels
            smoothedMeterLevel = 0
            lastErrorMessage = nil
            startMetering()
            return fileURL
        } catch let error as RecordingError {
            lastErrorMessage = error.localizedDescription
            throw error
        } catch {
            let nsError = error as NSError
            let reason = nsError.localizedFailureReason ?? nsError.localizedDescription
            let wrappedError = RecordingError.failedToPrepareRecorder(reason: reason)
            lastErrorMessage = wrappedError.localizedDescription
            throw wrappedError
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
        smoothedMeterLevel = 0
        lastErrorMessage = nil
    }

    private func startMetering() {
        stopMetering()

        meterTimer = Timer.scheduledTimer(withTimeInterval: Self.meterSampleInterval, repeats: true) { [weak self] _ in
            self?.captureMeterLevel()
        }
        meterTimer?.tolerance = 0.01
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
        let peakPower = recorder.peakPower(forChannel: 0)
        let normalizedAverage = Self.normalizedPower(from: averagePower, floor: Self.averageFloorDecibels)
        let normalizedPeak = Self.normalizedPower(from: peakPower, floor: Self.peakFloorDecibels)

        var blended = (normalizedAverage * 0.72) + (normalizedPeak * 0.28)
        if blended < Self.noiseGateThreshold {
            blended *= Self.noiseGateAttenuation
        }

        let smoothing = blended > smoothedMeterLevel
            ? Self.attackSmoothing
            : Self.releaseSmoothing
        smoothedMeterLevel += (blended - smoothedMeterLevel) * smoothing

        let displayLevel = max(Self.minimumDisplayLevel, min(CGFloat(1.0), smoothedMeterLevel))
        meterLevels.append(displayLevel)

        if meterLevels.count > Self.meterBarCount {
            meterLevels.removeFirst(meterLevels.count - Self.meterBarCount)
        }
    }

    private static func normalizedPower(from decibels: Float, floor: Float) -> CGFloat {
        guard decibels.isFinite else {
            return 0
        }

        let clampedDecibels = min(Float(0), max(floor, decibels))
        let linear = (clampedDecibels - floor) / abs(floor)
        return pow(CGFloat(linear), normalizationGamma)
    }

    private func makeDraftURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quoteapp-draft-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    private func makeRecorderSettings() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        let preferredSampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100

        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: preferredSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
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
