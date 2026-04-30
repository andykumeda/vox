import AVFoundation
import Foundation

public enum MeetingChunkerError: Error, CustomStringConvertible {
    case exportFailed(Error?)
    case zeroDurationAsset
    case noAudioTrack

    public var description: String {
        switch self {
        case .exportFailed(let e):
            return "Chunk export failed: \(e?.localizedDescription ?? "unknown")"
        case .zeroDurationAsset:
            return "Source asset reported zero duration."
        case .noAudioTrack:
            return "Source asset has no audio track."
        }
    }
}

public struct MeetingChunker {
    public let chunkDurationSeconds: Double

    public init(chunkDurationSeconds: Double = 300) {
        self.chunkDurationSeconds = chunkDurationSeconds
    }

    /// Split `input` into ordered AAC m4a chunks of at most `chunkDurationSeconds`,
    /// written into `outputDirectory` as `000.m4a`, `001.m4a`, …
    /// Returns the chunk URLs in order.
    public func split(input: URL, outputDirectory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )

        let asset = AVURLAsset(url: input)
        let totalDuration = try await asset.load(.duration).seconds
        guard totalDuration > 0 else { throw MeetingChunkerError.zeroDurationAsset }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw MeetingChunkerError.noAudioTrack }

        let chunkCount = Int(ceil(totalDuration / chunkDurationSeconds))
        var outputs: [URL] = []
        for i in 0..<chunkCount {
            let start = Double(i) * chunkDurationSeconds
            let duration = min(chunkDurationSeconds, totalDuration - start)
            let outURL = outputDirectory.appendingPathComponent(
                String(format: "%03d.m4a", i)
            )
            try? FileManager.default.removeItem(at: outURL)
            try await exportSegment(
                asset: asset,
                start: start,
                duration: duration,
                outputURL: outURL
            )
            outputs.append(outURL)
        }
        return outputs
    }

    private func exportSegment(
        asset: AVAsset, start: Double, duration: Double, outputURL: URL
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MeetingChunkerError.exportFailed(nil)
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        let timescale: CMTimeScale = 600
        let startTime = CMTime(seconds: start, preferredTimescale: timescale)
        let durationTime = CMTime(seconds: duration, preferredTimescale: timescale)
        exporter.timeRange = CMTimeRange(start: startTime, duration: durationTime)

        await exporter.export()
        switch exporter.status {
        case .completed:
            return
        default:
            throw MeetingChunkerError.exportFailed(exporter.error)
        }
    }
}
