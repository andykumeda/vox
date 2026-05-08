import AVFoundation
import Foundation

public enum MeetingAudioMixerError: Error, CustomStringConvertible {
    case noSources
    case noAudioTrack(URL)
    case exportFailed(Error?)

    public var description: String {
        switch self {
        case .noSources:              return "Mixer: no audio sources"
        case .noAudioTrack(let u):    return "Mixer: no audio track in \(u.lastPathComponent)"
        case .exportFailed(let e):    return "Mixer export failed: \(e?.localizedDescription ?? "unknown")"
        }
    }
}

/// Combines multiple meeting audio streams (mic + system loopback) into a
/// single m4a so a diarizing STT provider can speaker-tag everyone in one
/// pass. Each source is inserted at its absolute meeting-timeline offset
/// so overlapping speech overlaps in the mix.
public struct MeetingAudioMixer {
    public struct Source: Sendable {
        public let url: URL
        /// Composition insertion offset in seconds (absolute meeting timeline).
        public let startTime: Double
        public init(url: URL, startTime: Double) {
            self.url = url
            self.startTime = startTime
        }
    }

    public static func mix(sources: [Source], output: URL) async throws -> URL {
        guard !sources.isEmpty else { throw MeetingAudioMixerError.noSources }

        let composition = AVMutableComposition()
        let timescale: CMTimeScale = 600

        for src in sources {
            let asset = AVURLAsset(url: src.url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                throw MeetingAudioMixerError.noAudioTrack(src.url)
            }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }

            guard let comp = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            let insertAt = CMTime(seconds: max(0, src.startTime), preferredTimescale: timescale)
            try comp.insertTimeRange(timeRange, of: track, at: insertAt)
        }

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MeetingAudioMixerError.exportFailed(nil)
        }
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else {
            throw MeetingAudioMixerError.exportFailed(exporter.error)
        }
        return output
    }
}
