import AVFoundation
import Foundation

public struct AudibleBounds: Equatable {
    public let firstAudibleSec: Double
    public let lastAudibleSec: Double
    public let totalDurationSec: Double
    /// Whether any sample exceeded the silence threshold during the scan.
    /// Required because a fully-silent file produces firstAudibleSec=0 /
    /// lastAudibleSec=totalDurationSec by the prior coercion path, and a
    /// duration-only check would call any silent file longer than 100ms
    /// "audible" — sending pure silence to Whisper which then hallucinates.
    public let hadAudibleSamples: Bool

    public init(
        firstAudibleSec: Double,
        lastAudibleSec: Double,
        totalDurationSec: Double,
        hadAudibleSamples: Bool
    ) {
        self.firstAudibleSec = firstAudibleSec
        self.lastAudibleSec = lastAudibleSec
        self.totalDurationSec = totalDurationSec
        self.hadAudibleSamples = hadAudibleSamples
    }

    public var hasAudibleContent: Bool {
        hadAudibleSamples && lastAudibleSec - firstAudibleSec > 0.1
    }
}

public enum SilenceTrimError: Error, CustomStringConvertible {
    case exportFailed(Error?)
    case noAudibleContent

    public var description: String {
        switch self {
        case .exportFailed(let e):
            return "Silence trim export failed: \(e?.localizedDescription ?? "unknown")"
        case .noAudibleContent:
            return "Audio file contains no audible content above silence threshold."
        }
    }
}

/// Detects leading and trailing silence in a recorded m4a / scans PCM in 100ms windows
/// and reports the first/last window above an RMS threshold. Used by
/// MeetingTranscriptionSession to clip silent prefix/suffix before sending chunks to
/// Whisper so the model doesn't hallucinate over silence and so per-segment timestamps
/// stay anchored to real speech.
public enum SilenceTrim {
    /// ~-46 dBFS — well above floor noise, well below normal speech.
    public static let rmsThreshold: Float = 0.005
    public static let windowSec: Double = 0.1

    public static func detectBounds(url: URL) throws -> AudibleBounds {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalFrames = file.length
        let totalDur = Double(totalFrames) / sampleRate
        let windowFrames = AVAudioFrameCount(max(1, Int(sampleRate * windowSec)))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
            // Buffer alloc failed — we can't scan, so we cannot claim
            // there was audible content. Conservative fail-closed.
            return AudibleBounds(
                firstAudibleSec: 0,
                lastAudibleSec: totalDur,
                totalDurationSec: totalDur,
                hadAudibleSamples: false
            )
        }

        var firstAudible: Double? = nil
        var lastAudible: Double? = nil
        var pos: Int64 = 0

        while pos < totalFrames {
            do {
                try file.read(into: buf, frameCount: windowFrames)
            } catch {
                break
            }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let data = buf.floatChannelData else {
                pos += Int64(n)
                continue
            }
            var sumSq: Float = 0
            for f in 0..<n {
                for c in 0..<channels {
                    let s = data[c][f]
                    sumSq += s * s
                }
            }
            let rms = sqrt(sumSq / Float(n * channels))
            if rms > rmsThreshold {
                let secStart = Double(pos) / sampleRate
                let secEnd = Double(pos + Int64(n)) / sampleRate
                if firstAudible == nil { firstAudible = secStart }
                lastAudible = secEnd
            }
            pos += Int64(n)
        }

        return AudibleBounds(
            firstAudibleSec: firstAudible ?? 0,
            lastAudibleSec: lastAudible ?? totalDur,
            totalDurationSec: totalDur,
            hadAudibleSamples: firstAudible != nil
        )
    }

    /// Exports `[bounds.firstAudibleSec - padding, bounds.lastAudibleSec + padding]` of
    /// `input` into `output` using passthrough (no re-encode). Padding gives Whisper a
    /// touch of context on either side so first/last words don't get cut.
    public static func trim(
        input: URL,
        output: URL,
        bounds: AudibleBounds,
        padding: Double = 0.25
    ) async throws {
        guard bounds.hasAudibleContent else { throw SilenceTrimError.noAudibleContent }
        try? FileManager.default.removeItem(at: output)
        let asset = AVURLAsset(url: input)
        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough
        ) else {
            throw SilenceTrimError.exportFailed(nil)
        }
        let start = max(0, bounds.firstAudibleSec - padding)
        let end = min(bounds.totalDurationSec, bounds.lastAudibleSec + padding)
        export.outputURL = output
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        await export.export()
        if export.status != .completed {
            throw SilenceTrimError.exportFailed(export.error)
        }
    }
}
