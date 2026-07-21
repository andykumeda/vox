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
        endedAt: Date? = nil,
        status: TranscriptSession.Status = .completed,
        audioRetained: Bool = false
    ) -> TranscriptSession {
        TranscriptSession(
            id: id, title: "S", startedAt: startedAt, endedAt: endedAt,
            status: status, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: audioRetained
        )
    }

    private func writeFixture(byteCount: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xA5, count: byteCount).write(to: url)
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

    func testPurgeAudioRemovesEverySessionAudioArtifactAndPreservesNonAudioFiles() throws {
        let session = makeSession(audioRetained: true)
        try store.save(session)
        let sessionDirectory = store.sessionDirectory(id: session.id)
        let audioFiles = [
            store.audioFile(id: session.id),
            store.micFile(id: session.id),
            store.phoneFile(id: session.id),
            sessionDirectory.appendingPathComponent("audio-trimmed.m4a"),
            sessionDirectory.appendingPathComponent("mic-trimmed.m4a"),
            sessionDirectory.appendingPathComponent("phone-trimmed.m4a"),
            sessionDirectory.appendingPathComponent("mixed.m4a"),
            sessionDirectory.appendingPathComponent("mic.part0.m4a"),
            sessionDirectory.appendingPathComponent("mic.concat.m4a"),
            sessionDirectory
                .appendingPathComponent("derived", isDirectory: true)
                .appendingPathComponent("nested.m4a"),
        ]
        for (index, url) in audioFiles.enumerated() {
            try writeFixture(byteCount: index + 1, to: url)
        }

        let chunkDirectories = [
            store.chunksDirectory(id: session.id),
            store.chunksDirectory(id: session.id, source: .local),
            store.chunksDirectory(id: session.id, source: .remote),
        ]
        for directory in chunkDirectories {
            try writeFixture(
                byteCount: 3,
                to: directory.appendingPathComponent("000.m4a")
            )
        }

        let notesFile = sessionDirectory.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: notesFile)

        try store.purgeAudio(for: session.id)

        for url in audioFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "Expected purge to remove \(url.lastPathComponent)"
            )
        }
        for directory in chunkDirectories {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.path),
                "Expected purge to remove \(directory.lastPathComponent)"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesFile.path))
        XCTAssertEqual(try String(contentsOf: notesFile, encoding: .utf8), "keep me")

        let loaded = try XCTUnwrap(store.load(id: session.id))
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.title, session.title)
        XCTAssertEqual(loaded.status, session.status)
        XCTAssertFalse(loaded.audioRetained)
    }

    func testAudioDiskBytesCountsEverySessionAudioFileRecursively() throws {
        let session = makeSession(audioRetained: true)
        try store.save(session)
        let sessionDirectory = store.sessionDirectory(id: session.id)
        let fixtures: [(URL, Int)] = [
            (store.audioFile(id: session.id), 1),
            (store.micFile(id: session.id), 2),
            (store.phoneFile(id: session.id), 3),
            (sessionDirectory.appendingPathComponent("audio-trimmed.m4a"), 4),
            (sessionDirectory.appendingPathComponent("mic-trimmed.m4a"), 5),
            (sessionDirectory.appendingPathComponent("phone-trimmed.m4a"), 6),
            (sessionDirectory.appendingPathComponent("mixed.m4a"), 7),
            (sessionDirectory.appendingPathComponent("mic.part0.m4a"), 8),
            (sessionDirectory.appendingPathComponent("mic.concat.m4a"), 9),
            (
                store.chunksDirectory(id: session.id)
                    .appendingPathComponent("000.m4a"),
                10
            ),
            (
                store.chunksDirectory(id: session.id, source: .local)
                    .appendingPathComponent("000.m4a"),
                11
            ),
            (
                store.chunksDirectory(id: session.id, source: .remote)
                    .appendingPathComponent("000.m4a"),
                12
            ),
            (
                sessionDirectory
                    .appendingPathComponent("derived", isDirectory: true)
                    .appendingPathComponent("nested.m4a"),
                13
            ),
        ]
        for (url, byteCount) in fixtures {
            try writeFixture(byteCount: byteCount, to: url)
        }
        try writeFixture(
            byteCount: 100,
            to: sessionDirectory.appendingPathComponent("notes.txt")
        )

        XCTAssertEqual(
            store.audioDiskBytes(),
            UInt64(fixtures.reduce(0) { $0 + $1.1 })
        )
    }

    func testRetentionSweepRecoversLeakedAudioWhenSessionFlagIsAlreadyFalse() throws {
        let endedAt = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(
            endedAt: endedAt,
            status: .completed,
            audioRetained: false
        )
        try store.save(session)
        let leakedFile = store.sessionDirectory(id: session.id)
            .appendingPathComponent("audio-trimmed.m4a")
        let leakedChunk = store.chunksDirectory(id: session.id)
            .appendingPathComponent("000.m4a")
        try writeFixture(byteCount: 7, to: leakedFile)
        try writeFixture(byteCount: 11, to: leakedChunk)

        let purged = store.purgeAudioOlderThan(
            Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(purged, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leakedFile.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.chunksDirectory(id: session.id).path
            )
        )
        XCTAssertFalse(try XCTUnwrap(store.load(id: session.id)).audioRetained)
    }

    func testConditionalUpdateCannotResurrectAConcurrentlyDeletedSession() throws {
        let session = makeSession(status: .completed)
        try store.save(session)
        let deletingStore = MeetingTranscriptStore(rootDirectory: tempRoot)
        let predicateEntered = DispatchSemaphore(value: 0)
        let releaseUpdate = DispatchSemaphore(value: 0)
        let deleteStarted = DispatchSemaphore(value: 0)
        let updateFinished = expectation(description: "conditional update finished")
        let deleteFinished = expectation(description: "delete finished")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? self.store.updateIfPresent(
                id: session.id,
                matching: { _ in
                    predicateEntered.signal()
                    releaseUpdate.wait()
                    return true
                },
                mutate: { $0.summary = "late summary" }
            )
            updateFinished.fulfill()
        }
        XCTAssertEqual(predicateEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            deleteStarted.signal()
            try? deletingStore.delete(id: session.id)
            deleteFinished.fulfill()
        }
        XCTAssertEqual(deleteStarted.wait(timeout: .now() + 1), .success)
        releaseUpdate.signal()

        wait(for: [updateFinished, deleteFinished], timeout: 2)
        XCTAssertNil(store.load(id: session.id))
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

    func testPurgeAudioOlderThanRemovesOldKeepsRecent() throws {
        let now = Date()
        let oldSession = TranscriptSession(
            id: UUID(), title: "old", startedAt: now.addingTimeInterval(-100_000),
            endedAt: now.addingTimeInterval(-90_000), status: .completed,
            chunksTotal: 0, chunksCompleted: 0, segments: [], audioRetained: true
        )
        let recent = TranscriptSession(
            id: UUID(), title: "recent", startedAt: now.addingTimeInterval(-100),
            endedAt: now.addingTimeInterval(-50), status: .completed,
            chunksTotal: 0, chunksCompleted: 0, segments: [], audioRetained: true
        )
        try store.save(oldSession)
        try store.save(recent)
        try Data([0]).write(to: store.audioFile(id: oldSession.id))
        try Data([0]).write(to: store.audioFile(id: recent.id))

        let purged = store.purgeAudioOlderThan(now.addingTimeInterval(-1000))
        XCTAssertEqual(purged, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioFile(id: oldSession.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFile(id: recent.id).path))
        // Transcript JSON for purged session is preserved.
        XCTAssertNotNil(store.load(id: oldSession.id))
        XCTAssertEqual(store.load(id: oldSession.id)?.audioRetained, false)
    }

    func testPurgeAudioOlderThanSkipsInFlight() throws {
        let now = Date()
        let inflight = TranscriptSession(
            id: UUID(), title: "inflight", startedAt: now.addingTimeInterval(-100_000),
            endedAt: now.addingTimeInterval(-90_000), status: .recording,
            chunksTotal: 0, chunksCompleted: 0, segments: [], audioRetained: true
        )
        try store.save(inflight)
        try Data([0]).write(to: store.audioFile(id: inflight.id))
        let purged = store.purgeAudioOlderThan(now.addingTimeInterval(-1000))
        XCTAssertEqual(purged, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFile(id: inflight.id).path))
    }

    func testListReturnsEmptyWhenRootMissing() {
        let empty = MeetingTranscriptStore(
            rootDirectory: tempRoot.appendingPathComponent("does-not-exist")
        )
        XCTAssertEqual(empty.list(), [])
    }
}
