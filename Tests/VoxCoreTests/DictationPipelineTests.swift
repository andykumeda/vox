import Foundation
import XCTest
@testable import VoxCore

final class DictationPipelineTests: XCTestCase {
    func testSilenceStopsBeforeTranscription() async {
        let pipeline = DictationPipeline { _, _ in
            XCTFail("Transcription must not run for silence")
            return "unexpected"
        }
        let recording = DictationRecording(
            wav: Data(),
            metrics: WAVAudioMetrics(durationSec: 0.2, rms: 10, voicedDurationSec: 0)
        )

        do {
            _ = try await pipeline.transcribe(
                recording: recording,
                configuration: DictationConfiguration()
            )
            XCTFail("Expected noSpeech")
        } catch {
            XCTAssertEqual(error as? DictationPipelineError, .noSpeech)
        }
    }

    func testPipelinePostProcessesCleansAndProtectsDictionary() async throws {
        let dictionary = DictionaryEntry(
            id: "vox-name",
            spoken: "box",
            replacement: "Vox",
            mode: .prose
        )
        let pipeline = DictationPipeline(
            transcribe: { _, _ in "I use box for dictation" },
            llmCleaner: { _ in "I use Vox for dictation." }
        )
        let recording = DictationRecording(
            wav: Data([0]),
            metrics: WAVAudioMetrics(durationSec: 2, rms: 1_000, voicedDurationSec: 1)
        )

        let result = try await pipeline.transcribe(
            recording: recording,
            configuration: DictationConfiguration(dictionaryEntries: [dictionary])
        )

        XCTAssertEqual(result.rawText, "I use box for dictation")
        XCTAssertEqual(result.text, "I use Vox for dictation.")
    }

    func testSpokenDigitSequenceIsNotAddedTogether() async throws {
        let pipeline = DictationPipeline { _, _ in "Testing one two three." }
        let recording = DictationRecording(
            wav: Data([0]),
            metrics: WAVAudioMetrics(durationSec: 2, rms: 1_000, voicedDurationSec: 1)
        )
        let result = try await pipeline.transcribe(
            recording: recording, configuration: DictationConfiguration()
        )
        XCTAssertEqual(result.rawText, "Testing one two three.")
        XCTAssertEqual(result.text, "Testing 1 2 3.")
    }

    func testGenuinePoliteSpeechSurvivesPipeline() async throws {
        let pipeline = DictationPipeline { _, _ in "Thank you." }
        let recording = DictationRecording(
            wav: Data([0]),
            metrics: WAVAudioMetrics(durationSec: 1.2, rms: 800, voicedDurationSec: 0.6)
        )
        let result = try await pipeline.transcribe(
            recording: recording, configuration: DictationConfiguration()
        )
        XCTAssertEqual(result.rawText, "Thank you.")
        XCTAssertEqual(result.text, "Thank you.")
    }

    func testRunawayTranscriptionIsSuppressed() async {
        let pipeline = DictationPipeline { _, _ in String(repeating: "word ", count: 100) }
        let recording = DictationRecording(
            wav: Data([0]),
            metrics: WAVAudioMetrics(durationSec: 2, rms: 1_000, voicedDurationSec: 1)
        )

        do {
            _ = try await pipeline.transcribe(
                recording: recording,
                configuration: DictationConfiguration()
            )
            XCTFail("Expected suspectedHallucination")
        } catch {
            XCTAssertEqual(error as? DictationPipelineError, .suspectedHallucination)
        }
    }

    func testCleanupCannotRemoveLargeNumberGroupingFromDeliveredProse() async throws {
        let pipeline = DictationPipeline(
            transcribe: { _, _ in "The total is 300000" },
            llmCleaner: { _ in "The total is 300000." }
        )
        let recording = DictationRecording(
            wav: Data([0]),
            metrics: WAVAudioMetrics(durationSec: 2, rms: 1_000, voicedDurationSec: 1)
        )

        let result = try await pipeline.transcribe(recording: recording, configuration: DictationConfiguration())

        XCTAssertEqual(result.rawText, "The total is 300000")
        XCTAssertEqual(result.text, "The total is 300,000.")
    }
}
