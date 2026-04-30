import XCTest
@testable import vox

final class MeetingTranscriptStoreTests: XCTestCase {
    var tempRoot: URL!
    var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-tests-\(UUID().uuidString)")
        store = MeetingTranscriptStore(rootDirectory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testCodableRoundTrip() throws {
        let id = UUID()
        let session = TranscriptSession(
            id: id,
            title: "Test",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            status: .completed,
            chunksTotal: 2,
            chunksCompleted: 2,
            segments: [
                TranscriptSegment(startTime: 0, endTime: 5, text: "hello"),
                TranscriptSegment(startTime: 5, endTime: 10, text: "world"),
            ],
            audioRetained: false
        )
        try store.save(session)
        let loaded = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.title, "Test")
        XCTAssertEqual(loaded.segments.count, 2)
        XCTAssertEqual(loaded.segments[0].text, "hello")
        XCTAssertEqual(loaded.status, .completed)
    }

    private func makeSession(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        status: TranscriptSession.Status = .completed,
        audioRetained: Bool = false
    ) -> TranscriptSession {
        TranscriptSession(
            id: id, title: "S", startedAt: startedAt, endedAt: nil,
            status: status, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: audioRetained
        )
    }

    func testListOrderingByDateDesc() throws {
        let older = makeSession(startedAt: Date(timeIntervalSince1970: 100))
        let newer = makeSession(startedAt: Date(timeIntervalSince1970: 200))
        try store.save(older)
        try store.save(newer)
        let listed = store.list()
        XCTAssertEqual(listed.map(\.id), [newer.id, older.id])
    }

    func testDeleteRemovesDirectory() throws {
        let s = makeSession()
        try store.save(s)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sessionDirectory(id: s.id).path))
        try store.delete(id: s.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sessionDirectory(id: s.id).path))
    }

    func testPurgeAudioKeepsTranscript() throws {
        let s = makeSession(audioRetained: true)
        try store.save(s)
        try Data([0]).write(to: store.audioFile(id: s.id))
        try store.purgeAudio(for: s.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioFile(id: s.id).path))
        let loaded = try XCTUnwrap(store.load(id: s.id))
        XCTAssertFalse(loaded.audioRetained)
    }

    func testRecoverInFlightSessionsResetsToFailed() throws {
        let inFlight = [TranscriptSession.Status.recording, .chunking, .transcribing]
        var ids: [UUID] = []
        for status in inFlight {
            let s = makeSession(status: status)
            try store.save(s)
            ids.append(s.id)
        }
        let completed = makeSession(status: .completed)
        try store.save(completed)

        store.recoverInFlightSessions()

        for id in ids {
            XCTAssertEqual(store.load(id: id)?.status, .failed)
            XCTAssertNotNil(store.load(id: id)?.endedAt)
        }
        XCTAssertEqual(store.load(id: completed.id)?.status, .completed)
    }

    func testListReturnsEmptyWhenRootMissing() {
        let empty = MeetingTranscriptStore(
            rootDirectory: tempRoot.appendingPathComponent("does-not-exist")
        )
        XCTAssertEqual(empty.list(), [])
    }
}
