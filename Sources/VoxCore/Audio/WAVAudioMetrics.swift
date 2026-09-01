import Foundation

public struct WAVAudioMetrics: Equatable, Sendable {
    public let durationSec: Double
    public let rms: Double
    public let voicedDurationSec: Double

    public init(durationSec: Double, rms: Double, voicedDurationSec: Double) {
        self.durationSec = durationSec
        self.rms = rms
        self.voicedDurationSec = voicedDurationSec
    }

    public static func analyze(_ wav: Data) -> WAVAudioMetrics? {
        guard wav.count >= 44,
              String(data: wav[0..<4], encoding: .ascii) == "RIFF",
              String(data: wav[8..<12], encoding: .ascii) == "WAVE"
        else { return nil }

        var offset = 12
        var sampleRate: Int?
        var channelCount: Int?
        var bitsPerSample: Int?
        var pcmRange: Range<Int>?

        while offset + 8 <= wav.count {
            guard let chunkSize = littleEndianUInt32(wav, at: offset + 4) else { return nil }
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + Int(chunkSize)
            guard payloadEnd <= wav.count else { return nil }
            let chunkID = String(data: wav[offset..<(offset + 4)], encoding: .ascii)

            if chunkID == "fmt ", payloadEnd - payloadStart >= 16 {
                guard littleEndianUInt16(wav, at: payloadStart) == 1,
                      let channels = littleEndianUInt16(wav, at: payloadStart + 2),
                      let rate = littleEndianUInt32(wav, at: payloadStart + 4),
                      let bits = littleEndianUInt16(wav, at: payloadStart + 14)
                else { return nil }
                channelCount = Int(channels)
                sampleRate = Int(rate)
                bitsPerSample = Int(bits)
            } else if chunkID == "data" {
                pcmRange = payloadStart..<payloadEnd
            }

            offset = payloadEnd + (Int(chunkSize) % 2)
        }

        guard let sampleRate, sampleRate > 0,
              let channelCount, channelCount > 0,
              bitsPerSample == 16,
              let pcmRange,
              !pcmRange.isEmpty
        else { return nil }

        let pcm = wav[pcmRange]
        let sampleCount = pcm.count / MemoryLayout<Int16>.size
        guard sampleCount >= channelCount else { return nil }

        var sumSquares = 0.0
        var monoSamples: [Double] = []
        monoSamples.reserveCapacity(sampleCount / channelCount)
        var index = pcm.startIndex
        while index + 1 < pcm.endIndex {
            var channelSum = 0.0
            for _ in 0..<channelCount where index + 1 < pcm.endIndex {
                let value = Int16(bitPattern: UInt16(pcm[index]) | (UInt16(pcm[index + 1]) << 8))
                let sample = Double(value)
                sumSquares += sample * sample
                channelSum += sample
                index += 2
            }
            monoSamples.append(channelSum / Double(channelCount))
        }

        let rms = sqrt(sumSquares / Double(sampleCount))
        let frameSampleCount = max(1, Int(Double(sampleRate) * 0.020))
        var voicedFrames = 0
        var frameStart = 0
        while frameStart + frameSampleCount <= monoSamples.count {
            var frameSumSquares = 0.0
            for sample in monoSamples[frameStart..<(frameStart + frameSampleCount)] {
                frameSumSquares += sample * sample
            }
            let frameRMS = sqrt(frameSumSquares / Double(frameSampleCount))
            if frameRMS >= DictationSilenceGate.speechActivityFrameRMS {
                voicedFrames += 1
            }
            frameStart += frameSampleCount
        }

        return WAVAudioMetrics(
            durationSec: Double(monoSamples.count) / Double(sampleRate),
            rms: rms,
            voicedDurationSec: Double(voicedFrames) * 0.020
        )
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
