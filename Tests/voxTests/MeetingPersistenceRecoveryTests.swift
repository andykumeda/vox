import XCTest
@testable import vox

final class MeetingPersistenceRecoveryTests: XCTestCase {
    func testFinalSaveFailureDoesNotReportCompletionOrDeleteAudio() async throws {
        struct SaveFailure: Error {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        let chunk = root.appendingPathComponent("fixture.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0]).write(to: chunk)
        var failFinalSave = true
        var reported = false
        let session = MeetingTranscriptionSession(
            store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "saved text")] },
            apiKey: { "test" }, preflight: { .success(()) },
            saveSession: { candidate in
                if failFinalSave && candidate.status == .completed { throw SaveFailure() }
                try store.save(candidate)
            }, reportSaveFailure: { _ in reported = true })
        try await session.start()
        let id = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .failed)
        XCTAssertTrue(session.failureReasonSnapshot?.contains("could not be saved") ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFile(id: id).path))
        XCTAssertNotEqual(store.load(id: id)?.status, .completed)
        XCTAssertTrue(reported)
        do {
            try await session.start()
            XCTFail("A new meeting must not replace an unsaved transcript")
        } catch is SaveFailure { }
        XCTAssertEqual(session.activeSessionID, id)
        failFinalSave = false
        try await session.start()
        XCTAssertEqual(store.load(id: id)?.segments.first?.text, "saved text")
        try await session.stop()
        await session.waitForCompletion()
    }
}
