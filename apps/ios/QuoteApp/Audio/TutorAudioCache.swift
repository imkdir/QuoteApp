import CryptoKit
import Foundation

final class TutorAudioCache {
    struct CachedAudioMetadata: Codable, Equatable {
        let estimatedDurationSeconds: TimeInterval?
        let rhythmWordEndTimes: [TimeInterval]
    }

    struct CachedAudioArtifact: Equatable {
        let fileURL: URL
        let metadata: CachedAudioMetadata?
    }

    enum CacheError: LocalizedError {
        case cacheDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .cacheDirectoryUnavailable:
                return "Tutor audio cache directory is unavailable."
            }
        }
    }

    private let fileManager: FileManager
    private let cacheDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        baseCacheDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let baseDirectory =
            baseCacheDirectoryURL ??
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.cacheDirectoryURL =
            (baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("TutorPlaybackAudioCache", isDirectory: true)
    }

    func cachedAudioArtifact(for playbackIdentity: String) -> CachedAudioArtifact? {
        guard !playbackIdentity.isEmpty else {
            return nil
        }

        let artifactURL = audioArtifactURL(for: playbackIdentity)
        guard fileManager.fileExists(atPath: artifactURL.path) else {
            return nil
        }

        return CachedAudioArtifact(
            fileURL: artifactURL,
            metadata: readMetadata(for: playbackIdentity)
        )
    }

    @discardableResult
    func storeAudioArtifact(
        data: Data,
        playbackIdentity: String,
        metadata: CachedAudioMetadata?
    ) throws -> URL {
        guard !playbackIdentity.isEmpty else {
            throw CacheError.cacheDirectoryUnavailable
        }

        try ensureCacheDirectoryExists()
        let artifactURL = audioArtifactURL(for: playbackIdentity)
        try data.write(to: artifactURL, options: .atomic)
        try writeMetadata(metadata, for: playbackIdentity)
        return artifactURL
    }

    private func ensureCacheDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: cacheDirectoryURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            throw CacheError.cacheDirectoryUnavailable
        }

        try fileManager.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func audioArtifactURL(for playbackIdentity: String) -> URL {
        let digest = SHA256.hash(data: Data(playbackIdentity.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectoryURL.appendingPathComponent("\(hex).wav")
    }

    private func metadataURL(for playbackIdentity: String) -> URL {
        let digest = SHA256.hash(data: Data(playbackIdentity.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectoryURL.appendingPathComponent("\(hex).json")
    }

    private func writeMetadata(
        _ metadata: CachedAudioMetadata?,
        for playbackIdentity: String
    ) throws {
        let destination = metadataURL(for: playbackIdentity)
        guard let metadata else {
            try? fileManager.removeItem(at: destination)
            return
        }

        let data = try JSONEncoder().encode(metadata)
        try data.write(to: destination, options: .atomic)
    }

    private func readMetadata(for playbackIdentity: String) -> CachedAudioMetadata? {
        let source = metadataURL(for: playbackIdentity)
        guard let data = try? Data(contentsOf: source) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedAudioMetadata.self, from: data)
    }
}
