import XCTest
@testable import vox

final class MeetingAutoRecoveryTests: XCTestCase {
    private let key = Data(repeating: 0x7C, count: 32)
    private var root: URL!
    private var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vox-auto-recovery-\(UUID().uuidString)")
        store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { self.key },
                                       retention: { .init(enabled: false, days: .seven) })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func failedMeeting() throws -> (TranscriptSession, URL) {
        let id = UUID()
        let record = TranscriptSession(id: id, title: "A meeting", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060), status: .failed,
            chunksTotal: 2, chunksCompleted: 1,
            rawSegments: [TranscriptSegment(startTime: 0, endTime: 1, text: "raw partial")],
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "old partial")],
            audioRetained: true, failureReason: "A request failed", summary: "previous summary",
            sourceOffsets: .init(system: 0, microphone: 0, phone: 0), sourceAvailability: [true, false, false])
        try store.save(record)
        let source = store.audioFile(id: id)
        try Data("synthetic source".utf8).write(to: source)
        let archive = source.appendingPathExtension("enc")
        try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
        try FileManager.default.removeItem(at: source)
        return (record, archive)
    }

    private func pipeline(transcribe: @escaping MeetingTranscriptionSession.Transcribe) -> MeetingTranscriptionSession {
        MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { input, _ in [input] }, transcribe: transcribe,
            apiKey: { "test" }, preflight: { .success(()) }, backoffSchedule: [0.001], retryBudget: 0.05)
    }

    func testSuccessfulRecoveryReplacesPartialUnderSameMeetingID() async throws {
        let (old, archive) = try failedMeeting()
        let session = pipeline { url, _, _ in
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), "Original must survive every upload")
            XCTAssertEqual(try Data(contentsOf: url), Data("synthetic source".utf8))
            return [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
        }
        try await session.recoverMeeting(id: old.id)
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.id, old.id)
        XCTAssertEqual(saved.title, old.title)
        XCTAssertEqual(saved.startedAt, old.startedAt)
        XCTAssertEqual(saved.status, .completed)
        XCTAssertEqual(saved.segments.map(\.text), ["recovered"])
        XCTAssertFalse(saved.segments.contains { $0.text == "old partial" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path), "Opted-out audio is eligible for cleanup only after durable completion")
    }

    func testFailedRecoveryPreservesExistingTranscriptAndOriginalArchive() async throws {
        struct ProviderFailure: Error {}
        let (old, archive) = try failedMeeting()
        let session = pipeline { _, _, _ in throw ProviderFailure() }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertEqual(saved.rawSegments, old.rawSegments)
        XCTAssertEqual(saved.summary, old.summary)
        XCTAssertEqual(saved.failureReason, old.failureReason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try MeetingAudioArchive.verify(archive: archive, key: key)
    }

    func testCorruptArchiveNeverUploadsAndPreservesPriorTranscript() async throws {
        let (old, archive) = try failedMeeting()
        try Data("corrupt".utf8).write(to: archive)
        let session = pipeline { _, _, _ in XCTFail("Corrupt audio must not reach a provider"); return [] }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertNotEqual(saved.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testMissingMultisourceAlignmentNeverClaimsComplete() async throws {
        var (old, _) = try failedMeeting()
        old.sourceAvailability = nil
        old.sourceOffsets = nil
        try store.save(old)
        let mic = store.micFile(id: old.id)
        try Data("mic".utf8).write(to: mic)
        try MeetingAudioArchive.encrypt(source: mic, destination: mic.appendingPathExtension("enc"), key: key)
        try FileManager.default.removeItem(at: mic)
        let session = pipeline { _, _, _ in XCTFail("Unaligned legacy streams must not be uploaded as a complete meeting"); return [] }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertNotEqual(saved.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mic.appendingPathExtension("enc").path))
    }
    func testCancellationPreservesExistingTranscriptAndAudio() async throws {
        let (old, archive) = try failedMeeting()
        let entered = AsyncSemaphore(initial: 0)
        let session = pipeline { _, _, _ in
            await entered.signal()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return []
        }
        let task = Task { try await session.recoverMeeting(id: old.id) }
        await entered.wait()
        task.cancel()
        _ = try? await task.value
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertNotEqual(saved.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try MeetingAudioArchive.verify(archive: archive, key: key)
    }

    func testLiveRecordingIsNotInterruptedByRecovery() async throws {
        let (old, archive) = try failedMeeting()
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in
            _ = await attempts.increment()
            return [TranscriptSegment(startTime: 0, endTime: 1, text: "current meeting")]
        }
        try await session.start()
        do { try await session.recoverMeeting(id: old.id) } catch { }
        XCTAssertTrue(session.isRecording)
        let count = await attempts.value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.load(id: old.id)?.segments, old.segments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try await session.stop()
        await session.waitForCompletion()
    }

    func testConflictingPlaintextAndArchiveAreNotUploadedOrDeleted() async throws {
        let (old, archive) = try failedMeeting()
        let source = store.audioFile(id: old.id)
        let different = Data("different possibly newer source".utf8)
        try different.write(to: source)
        let session = pipeline { _, _, _ in XCTFail("Conflicting sources require review"); return [] }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertNotEqual(saved.status, .completed)
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertEqual(try Data(contentsOf: source), different)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try MeetingAudioArchive.verify(archive: archive, key: key)
    }

    func testConcurrentRecoveryDoesNotUploadSameMeetingTwice() async throws {
        let (old, archive) = try failedMeeting()
        let entered = AsyncSemaphore(initial: 0)
        let resume = AsyncSemaphore(initial: 0)
        let attempts = AtomicInt()
        let session = pipeline { _, _, _ in
            _ = await attempts.increment()
            await entered.signal()
            await resume.wait()
            return [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
        }
        let first = Task { try await session.recoverMeeting(id: old.id) }
        await entered.wait()
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let count = await attempts.value
        XCTAssertEqual(count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        await resume.signal()
        _ = try? await first.value
    }

    func testExpectedMissingSourcePreventsUploadAndPreservesAudio() async throws {
        var (old, archive) = try failedMeeting()
        old.sourceOffsets = .init(system: 0, microphone: 2.5, phone: 0)
        old.sourceAvailability = [true, true, false]
        try store.save(old)
        let session = pipeline { _, _, _ in XCTFail("A missing recorded source must not be omitted silently"); return [] }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertNotEqual(saved.status, .completed)
        XCTAssertEqual(saved.segments, old.segments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testRecoveryUsesPersistedMultisourceOffsets() async throws {
        var (old, archive) = try failedMeeting()
        old.sourceOffsets = .init(system: 0, microphone: 2.5, phone: 0)
        old.sourceAvailability = [true, true, false]
        try store.save(old)
        let mic = store.micFile(id: old.id)
        try Data("mic".utf8).write(to: mic)
        let micArchive = mic.appendingPathExtension("enc")
        try MeetingAudioArchive.encrypt(source: mic, destination: micArchive, key: key)
        try FileManager.default.removeItem(at: mic)
        let session = pipeline { _, offset, source in
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: micArchive.path))
            return [TranscriptSegment(startTime: offset, endTime: offset + 1,
                                      text: source == .local ? "local" : "remote", source: source)]
        }
        try await session.recoverMeeting(id: old.id)
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertEqual(saved.status, .completed)
        let remote = try XCTUnwrap(saved.segments.first { $0.source == .remote })
        let local = try XCTUnwrap(saved.segments.first { $0.source == .local })
        XCTAssertEqual(remote.startTime, 0, accuracy: 0.001)
        XCTAssertEqual(local.startTime, 2.5, accuracy: 0.001)
    }

    func testLegacySingleSourceWithoutManifestCannotBeClaimedComplete() async throws {
        var (old, archive) = try failedMeeting()
        old.sourceAvailability = nil
        old.sourceOffsets = nil
        try store.save(old)
        let session = pipeline { _, _, _ in
            XCTFail("An absent source manifest requires review")
            return []
        }
        do { try await session.recoverMeeting(id: old.id) } catch { }
        let saved = try XCTUnwrap(store.load(id: old.id))
        XCTAssertNotEqual(saved.status, .completed, "An absent manifest does not prove other sources were never captured")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testSuccessfulRecoveryRegeneratesEnabledSummary() async throws {
        let (old, _) = try failedMeeting()
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { input, _ in [input] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "new result")] },
            apiKey: { "test" }, summarize: { segments in "Summary: " + segments[0].text },
            summarizeEnabled: { true }, preflight: { .success(()) }, backoffSchedule: [0.001], retryBudget: 0.05)
        try await session.recoverMeeting(id: old.id)
        XCTAssertEqual(store.load(id: old.id)?.summary, "Summary: new result")
    }

}
