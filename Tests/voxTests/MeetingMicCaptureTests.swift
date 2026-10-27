import AVFoundation
import XCTest
@testable import vox

final class MeetingMicCaptureTests: XCTestCase {
    private final class Recorder: MeetingMicrophoneRecording {
        var delegate: AVAudioRecorderDelegate?
        var succeeds = true
        var starts = 0
        var stops = 0
        func record() -> Bool { starts += 1; return succeeds }
        func stop() { stops += 1 }
    }

    func testQuietCaptureKeepsOneFileAndRejectsDestructiveSecondStart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("quiet.m4a")
        let recorder = Recorder()
        var creations = 0
        let capture = MeetingMicCapture(requestPermission: { true }, makeRecorder: { output in
            creations += 1
            // Encoded-file stand-in: quiet content must not trigger replacement or splitting.
            try Data(repeating: 0, count: 8192).write(to: output)
            return recorder
        })
        try await capture.start(outputURL: url)
        let original = try Data(contentsOf: url)
        do {
            try await capture.start(outputURL: url)
            XCTFail("A second start must not truncate the active capture")
        } catch MeetingMicCaptureError.alreadyRecording { }
        let stopped = try await capture.stop()
        XCTAssertEqual(stopped, url)
        XCTAssertEqual(try Data(contentsOf: stopped), original)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(recorder.starts, 1)
        XCTAssertEqual(recorder.stops, 1)
        XCTAssertNil(recorder.delegate)
        XCTAssertNil(capture.lastFailureReason)
        XCTAssertNotNil(capture.audioStartedAt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["quiet.m4a"])
    }

    func testStartFailureDoesNotPoisonNextSuccessfulCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        recorder.succeeds = false
        let capture = MeetingMicCapture(requestPermission: { true }, makeRecorder: { output in
            try Data(repeating: 0, count: 8192).write(to: output)
            return recorder
        })
        let url = root.appendingPathComponent("capture.m4a")
        do {
            try await capture.start(outputURL: url)
            XCTFail("Expected recorder start failure")
        } catch MeetingMicCaptureError.startFailed { }
        XCTAssertNotNil(capture.lastFailureReason)
        XCTAssertNil(capture.audioStartedAt)
        XCTAssertNil(recorder.delegate)
        recorder.succeeds = true
        try await capture.start(outputURL: url)
        XCTAssertNil(capture.lastFailureReason)
        _ = try await capture.stop()
        XCTAssertNil(capture.lastFailureReason)
    }

    func testUnexpectedSuccessfulFinishPreservesPartialAudioAndWarning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        let capture = MeetingMicCapture(requestPermission: { true }, makeRecorder: { output in
            try Data(repeating: 1, count: 8192).write(to: output)
            return recorder
        })
        let url = root.appendingPathComponent("partial.m4a")
        try await capture.start(outputURL: url)
        capture.recorderDidFinish(recorder, successfully: true)
        let result = try await capture.stop()
        XCTAssertEqual(result, url)
        XCTAssertEqual(try Data(contentsOf: result).count, 8192)
        XCTAssertNil(capture.lastFailureReason)
        XCTAssertEqual(capture.captureWarnings.count, 1)
        try await capture.start(outputURL: url)
        XCTAssertTrue(capture.captureWarnings.isEmpty)
        _ = try await capture.stop()
    }

    func testUnsuccessfulFinishReportsFailureAndIgnoresStaleRecorder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        let capture = MeetingMicCapture(requestPermission: { true }, makeRecorder: { output in
            try Data(repeating: 1, count: 8192).write(to: output)
            return recorder
        })
        try await capture.start(outputURL: root.appendingPathComponent("failed.m4a"))
        capture.recorderDidFinish(Recorder(), successfully: false)
        XCTAssertNil(capture.lastFailureReason)
        capture.recorderDidFinish(recorder, successfully: false)
        _ = try await capture.stop()
        XCTAssertTrue(capture.lastFailureReason?.contains("encoding failure") == true)
        XCTAssertTrue(capture.captureWarnings.isEmpty)
    }

    func testEmptyCaptureReportsFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = MeetingMicCapture(requestPermission: { true }, makeRecorder: { output in
            try Data().write(to: output)
            return Recorder()
        })
        try await capture.start(outputURL: root.appendingPathComponent("empty.m4a"))
        _ = try await capture.stop()
        XCTAssertTrue(capture.lastFailureReason?.contains("empty") == true)
    }
}
