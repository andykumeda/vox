import XCTest
import AVFoundation
@testable import vox

final class MeetingChunkerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-chunker-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Generate a silent AAC m4a via AVAudioFile (handles encoding internally).
    private func generateSilentM4A(durationSeconds: Double) throws -> URL {
        let url = tempDir.appendingPathComponent("input-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: url)

        let sampleRate: Double = 44100  // AAC encoder reliably accepts 44.1k mono
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let bufFormat = file.processingFormat
        let frameCapacity = AVAudioFrameCount(4096)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bufFormat, frameCapacity: frameCapacity) else {
            throw NSError(domain: "test", code: -1)
        }
        buffer.frameLength = frameCapacity
        // Buffer initialized to zero (silence).

        let totalFrames = AVAudioFramePosition(durationSeconds * sampleRate)
        var written: AVAudioFramePosition = 0
        while written < totalFrames {
            let remaining = totalFrames - written
            let toWrite = AVAudioFrameCount(min(AVAudioFramePosition(frameCapacity), remaining))
            buffer.frameLength = toWrite
            try file.write(from: buffer)
            written += AVAudioFramePosition(toWrite)
        }
        // Closing happens on dealloc when `file` goes out of scope.
        return url
    }

    func testTwelveMinuteAudioProducesThreeChunks() async throws {
        let input = try generateSilentM4A(durationSeconds: 720)  // 12 min
        let chunker = MeetingChunker(chunkDurationSeconds: 300)
        let outputDir = tempDir.appendingPathComponent("chunks")
        let chunks = try await chunker.split(input: input, outputDirectory: outputDir)

        XCTAssertEqual(chunks.count, 3)
        for url in chunks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        let asset0 = AVURLAsset(url: chunks[0])
        let asset2 = AVURLAsset(url: chunks[2])
        let dur0 = try await asset0.load(.duration).seconds
        let dur2 = try await asset2.load(.duration).seconds
        XCTAssertEqual(dur0, 300.0, accuracy: 1.0)
        XCTAssertEqual(dur2, 120.0, accuracy: 1.0)
    }

    func testShortAudioProducesSingleChunk() async throws {
        let input = try generateSilentM4A(durationSeconds: 60)
        let chunker = MeetingChunker(chunkDurationSeconds: 300)
        let outputDir = tempDir.appendingPathComponent("chunks")
        let chunks = try await chunker.split(input: input, outputDirectory: outputDir)
        XCTAssertEqual(chunks.count, 1)
    }
}
