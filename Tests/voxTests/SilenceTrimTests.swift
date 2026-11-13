import XCTest
import AVFoundation
@testable import vox

final class SilenceTrimTests: XCTestCase {

    func testDigitalSilenceCheckDoesNotDiscardQuietAudio() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
            buffer.frameLength = 4410
            buffer.floatChannelData![0][2000] = 0.00001
            try file.write(from: buffer)
        }
        XCTAssertFalse(try SilenceTrim.isDigitalSilence(url: url))
    }

    // MARK: - hasAudibleContent guard semantics

    func testHasAudibleContentRequiresSamplesAboveThreshold() {
        // Pre-fix bug: silent file longer than 100ms returned (0, totalDur)
        // and `hasAudibleContent` was true because duration > 0.1s. This
        // sent pure silence to Whisper and produced hallucinated text.
        let silent = AudibleBounds(
            firstAudibleSec: 0,
            lastAudibleSec: 60.0,
            totalDurationSec: 60.0,
            hadAudibleSamples: false
        )
        XCTAssertFalse(silent.hasAudibleContent,
                       "Silent file (no samples above threshold) must not be reported as audible.")
    }

    func testHasAudibleContentTrueWhenSamplesAndDurationOK() {
        let real = AudibleBounds(
            firstAudibleSec: 1.0,
            lastAudibleSec: 5.0,
            totalDurationSec: 10.0,
            hadAudibleSamples: true
        )
        XCTAssertTrue(real.hasAudibleContent)
    }

    func testHasAudibleContentRequiresAtLeast100msDuration() {
        // Even with samples, duration <= 100ms is treated as no content.
        let blip = AudibleBounds(
            firstAudibleSec: 1.0,
            lastAudibleSec: 1.05,  // 50ms
            totalDurationSec: 10.0,
            hadAudibleSamples: true
        )
        XCTAssertFalse(blip.hasAudibleContent)
    }
}
