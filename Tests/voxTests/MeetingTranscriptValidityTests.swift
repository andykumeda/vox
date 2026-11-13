import XCTest
@testable import vox

final class MeetingTranscriptValidityTests: XCTestCase {
    func testEmptyProviderResultDoesNotClaimComplete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        let chunk = root.appendingPathComponent("fixture.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0]).write(to: chunk)
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] }, transcribe: { _, _, _ in [] },
            apiKey: { "test" }, preflight: { .success(()) })
        try await session.start()
        let id = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .failed)
        XCTAssertEqual(store.load(id: id)?.status, .failed)
    }
    func testOneEmptyChunkKeepsMeetingIncomplete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let chunks = [root.appendingPathComponent("one.m4a"), root.appendingPathComponent("two.m4a")]
        for chunk in chunks { try Data([0]).write(to: chunk) }
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in chunks }, transcribe: { _, offset, _ in
                offset == 0 ? [TranscriptSegment(startTime: 0, endTime: 1, text: "some speech")] : []
            }, apiKey: { "test" }, preflight: { .success(()) })
        try await session.start()
        let id = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await session.waitForCompletion()
        let saved = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.segments.first?.text, "some speech")
        XCTAssertFalse(saved.captureWarnings.isEmpty)
    }

}
