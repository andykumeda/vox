import XCTest
@testable import vox

final class MeetingRecoverySchedulerTests: XCTestCase {
    private let key = Data(repeating: 0x5C, count: 32)
    private var root: URL!
    private var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vox-recovery-scheduler-\(UUID().uuidString)")
        store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { self.key },
                                       retention: { .init(enabled: false, days: .seven) })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func failedMeeting() throws -> (UUID, URL) {
        let id = UUID()
        let record = TranscriptSession(id: id, title: "Meeting", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060), status: .failed, chunksTotal: 1,
            chunksCompleted: 0, segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "partial")],
            audioRetained: true, failureReason: "Provider unavailable",
            sourceOffsets: .init(system: 0, microphone: 0, phone: 0), sourceAvailability: [true, false, false])
        try store.save(record)
        let source = store.audioFile(id: id)
        try Data("synthetic".utf8).write(to: source)
        let archive = source.appendingPathExtension("enc")
        try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
        try FileManager.default.removeItem(at: source)
        return (id, archive)
    }

    private func pipeline(_ transcribe: @escaping MeetingTranscriptionSession.Transcribe) -> MeetingTranscriptionSession {
        MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { input, _ in [input] }, transcribe: transcribe,
            apiKey: { "test" }, preflight: { .success(()) }, backoffSchedule: [0.001], retryBudget: 0.05)
    }

    @MainActor
    func testSweepRecoversFailedMeetingAndDoesNotUploadItTwice() async throws {
        let (id, _) = try failedMeeting()
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in
            _ = await attempts.increment()
            return [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
        }
        let scheduler = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { 100 })
        await scheduler.sweep()
        await scheduler.sweep()
        let count = await attempts.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load(id: id)?.status, .completed)
        XCTAssertEqual(store.load(id: id)?.segments.first?.text, "recovered")
    }

    @MainActor
    func testFailedSweepWaitsForConfiguredIntervalBeforeTryingAgain() async throws {
        struct Outage: Error {}
        let (id, archive) = try failedMeeting()
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in _ = await attempts.increment(); throw Outage() }
        var current: TimeInterval = 100
        let scheduler = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { current })
        await scheduler.sweep()
        await scheduler.sweep()
        var count = await attempts.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load(id: id)?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        current += 3601
        await scheduler.sweep()
        count = await attempts.value
        XCTAssertEqual(count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    @MainActor
    func testUnavailableRecoveryKeepsOriginalFailureReason() async throws {
        let (id, _) = try failedMeeting()
        var record = try XCTUnwrap(store.load(id: id))
        record.sourceAvailability = nil
        try store.save(record)
        let session = pipeline { _, _, _ in XCTFail("Missing manifest must not upload"); return [] }
        let scheduler = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { 100 })
        await scheduler.sweep()
        let saved = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(saved.failureReason, "Provider unavailable")
        XCTAssertTrue(saved.captureWarnings.contains { $0.contains("Automatic recovery:") })
    }

    @MainActor
    func testSweepDoesNotInterruptActiveRecording() async throws {
        let (id, archive) = try failedMeeting()
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in
            _ = await attempts.increment()
            return [TranscriptSegment(startTime: 0, endTime: 1, text: "meeting")]
        }
        let scheduler = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { 100 })
        try await session.start()
        await scheduler.sweep()
        let count = await attempts.value
        XCTAssertEqual(count, 0)
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(store.load(id: id)?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try await session.stop()
        await session.waitForCompletion()
    }
    @MainActor
    func testRetryIntervalSurvivesSchedulerRestart() async throws {
        struct Outage: Error {}
        let (id, archive) = try failedMeeting()
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in _ = await attempts.increment(); throw Outage() }
        var current: TimeInterval = 100
        let first = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { current })
        await first.sweep()
        let restarted = MeetingRecoveryScheduler(session: session, store: store, interval: { 3600 }, now: { current })
        await restarted.sweep()
        var count = await attempts.value
        XCTAssertEqual(count, 1, "Restarting Vox must not bypass the retry interval")
        XCTAssertEqual(store.load(id: id)?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        current += 3601
        await restarted.sweep()
        count = await attempts.value
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testStartupRemovesStalePrivateRecoveryAudio() throws {
        let parent = root.appendingPathComponent(".automatic-recovery", isDirectory: true)
        let stale = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unrelated = parent.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("synthetic audio".utf8).write(to: stale.appendingPathComponent("audio.m4a"))
        try MeetingRecoveryScheduler.cleanStaleScratch(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

}
