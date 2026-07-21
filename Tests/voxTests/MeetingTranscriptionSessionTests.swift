import XCTest
@testable import vox

final class MeetingTranscriptionSessionTests: XCTestCase {
    var tempRoot: URL!
    var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-session-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = MeetingTranscriptStore(rootDirectory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    final class MockRecorder: MeetingAudioRecording {
        var output: URL?
        private(set) var startCallCount = 0
        private(set) var stopCallCount = 0
        func start(outputURL: URL) async throws {
            startCallCount += 1
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0xFA, 0xCE]).write(to: outputURL)
            self.output = outputURL
        }
        func stop() async throws -> URL {
            stopCallCount += 1
            guard let out = output else {
                throw MeetingAudioCaptureError.notRecording
            }
            return out
        }
    }

    func testHappyPath() async throws {
        let recorder = MockRecorder()
        let chunkURLs = (0..<3).map { i in
            tempRoot.appendingPathComponent("chunk-\(i).m4a")
        }
        for url in chunkURLs {
            try Data([0]).write(to: url)
        }
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in chunkURLs },
            transcribe: { url, offset, _ in
                let i = chunkURLs.firstIndex(of: url)!
                return [TranscriptSegment(
                    startTime: offset, endTime: offset + 1.0,
                    text: "chunk \(i)"
                )]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )

        try await session.start()
        try await session.stop()
        await session.waitForCompletion()

        XCTAssertEqual(session.statusSnapshot, .completed)
        let id = session.activeSessionID!
        let stored = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(stored.segments.count, 3)
        XCTAssertEqual(stored.segments[0].text, "chunk 0")
    }

    func testTransientRetrySucceedsAfterFailures() async throws {
        let recorder = MockRecorder()
        let chunkURL = tempRoot.appendingPathComponent("chunk-0.m4a")
        try Data([0]).write(to: chunkURL)
        let attemptsBox = AtomicInt()
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [chunkURL] },
            transcribe: { _, offset, _ in
                let n = await attemptsBox.increment()
                if n < 3 {
                    throw TranscriptionError.transportError(URLError(.timedOut))
                }
                return [TranscriptSegment(startTime: offset, endTime: offset + 1, text: "ok")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) },
            backoffSchedule: [0.01, 0.01, 0.01]
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
        let attempts = await attemptsBox.value
        XCTAssertEqual(attempts, 3)
    }

    func testUserCancelMidUploadPreservesPartialSegments() async throws {
        let recorder = MockRecorder()
        let urls = (0..<5).map { tempRoot.appendingPathComponent("c-\($0).m4a") }
        for u in urls { try Data([0]).write(to: u) }
        let cancelAfter = AsyncSemaphore(initial: 0)
        let countBox = AtomicInt()
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in urls },
            transcribe: { _, offset, _ in
                let n = await countBox.increment()
                if n == 2 {
                    await cancelAfter.signal()
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    try Task.checkCancellation()
                }
                return [TranscriptSegment(startTime: offset, endTime: offset+1, text: "x")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        try await session.stop()
        await cancelAfter.wait()
        session.cancel()
        await session.waitForCompletion()

        XCTAssertEqual(session.statusSnapshot, .cancelled)
        let id = session.activeSessionID!
        let stored = try XCTUnwrap(store.load(id: id))
        XCTAssertGreaterThanOrEqual(stored.segments.count, 1)
        XCTAssertLessThan(stored.segments.count, 5)
    }

    func testAudioRetainedFalseDeletesAudio() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "x")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        let id = session.activeSessionID!
        let audioPath = store.audioFile(id: id).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioPath))
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioPath))
    }

    func testCanStartSecondSessionAfterFirstCompletes() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)

        try await session.start()
        XCTAssertEqual(session.statusSnapshot, .recording)
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
    }

    func testDelayedSummaryUpdatesOriginalSessionWithoutMutatingNewSession() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("summary-race.m4a")
        try Data([0]).write(to: url)
        let summaryStarted = AsyncSemaphore(initial: 0)
        let releaseSummary = AsyncSemaphore(initial: 0)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "session A")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            summarize: { _ in
                await summaryStarted.signal()
                await releaseSummary.wait()
                return "Summary for A"
            },
            summarizeEnabled: { true },
            preflight: { .success(()) }
        )

        try await session.start()
        let sessionAID = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await summaryStarted.wait()
        XCTAssertEqual(store.load(id: sessionAID)?.status, .completed)

        try await session.start()
        let sessionBID = try XCTUnwrap(session.activeSessionID)
        XCTAssertNotEqual(sessionAID, sessionBID)
        XCTAssertEqual(session.statusSnapshot, .recording)

        await releaseSummary.signal()
        await session.waitForCompletion()

        XCTAssertEqual(store.load(id: sessionAID)?.summary, "Summary for A")
        XCTAssertNil(store.load(id: sessionBID)?.summary)
        XCTAssertEqual(store.load(id: sessionBID)?.status, .recording)
        XCTAssertEqual(session.activeSessionID, sessionBID)
        XCTAssertEqual(session.statusSnapshot, .recording)
    }

    func testDelayedSummaryDoesNotResurrectDeletedSession() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("deleted-summary-race.m4a")
        try Data([0]).write(to: url)
        let summaryStarted = AsyncSemaphore(initial: 0)
        let releaseSummary = AsyncSemaphore(initial: 0)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "deleted session")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            summarize: { _ in
                await summaryStarted.signal()
                await releaseSummary.wait()
                return "Too late"
            },
            summarizeEnabled: { true },
            preflight: { .success(()) }
        )

        try await session.start()
        let sessionID = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await summaryStarted.wait()
        try store.delete(id: sessionID)
        XCTAssertNil(store.load(id: sessionID))

        await releaseSummary.signal()
        await session.waitForCompletion()

        XCTAssertNil(store.load(id: sessionID))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.sessionDirectory(id: sessionID).path)
        )
    }

    func testDelayedSummaryDoesNotAttachToAChangedTranscript() async throws {
        let recorder = MockRecorder()
        let chunkURL = tempRoot.appendingPathComponent("summary-revision.m4a")
        try Data([0]).write(to: chunkURL)
        let summaryStarted = AsyncSemaphore(initial: 0)
        let releaseSummary = AsyncSemaphore(initial: 0)
        let originalSegments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "original transcript"),
        ]
        let replacementSegments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "replacement transcript"),
        ]
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [chunkURL] },
            transcribe: { _, _, _ in originalSegments },
            apiKey: { "sk-test" },
            retainAudio: { false },
            summarize: { segments in
                XCTAssertEqual(segments, originalSegments)
                await summaryStarted.signal()
                await releaseSummary.wait()
                return "Summary of the original transcript"
            },
            summarizeEnabled: { true },
            preflight: { .success(()) }
        )

        try await session.start()
        let sessionID = try XCTUnwrap(session.activeSessionID)
        try await session.stop()
        await summaryStarted.wait()

        var persisted = try XCTUnwrap(store.load(id: sessionID))
        persisted.segments = replacementSegments
        persisted.summary = nil
        try store.save(persisted)

        await releaseSummary.signal()
        await session.waitForCompletion()

        let reloaded = try XCTUnwrap(store.load(id: sessionID))
        XCTAssertEqual(reloaded.segments, replacementSegments)
        XCTAssertNil(reloaded.summary)
    }

    func testFailedDeepgramRetranscriptionPreservesExistingTranscript() async throws {
        let sessionID = UUID()
        let originalSegments = [
            TranscriptSegment(
                startTime: 0,
                endTime: 2,
                text: "Original transcript",
                source: .remote
            ),
        ]
        let original = TranscriptSession(
            id: sessionID,
            title: "Existing meeting",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_100),
            status: .completed,
            chunksTotal: 1,
            chunksCompleted: 1,
            segments: originalSegments,
            audioRetained: true,
            summary: "Original summary"
        )
        try store.save(original)
        try Data([0xFA, 0xCE]).write(to: store.audioFile(id: sessionID))

        let session = MeetingTranscriptionSession(
            store: store,
            recorder: MockRecorder(),
            chunker: { _, _ in [] },
            transcribe: { _, _, _ in [] },
            deepgramTranscribe: { _ in
                throw TranscriptionError.transportError(URLError(.timedOut))
            },
            apiKey: { "sk-test" },
            retainAudio: { true },
            preflight: { .success(()) }
        )

        await session.reTranscribeWithDeepgram(sessionID: sessionID)

        let stored = try XCTUnwrap(store.load(id: sessionID))
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.segments, originalSegments)
        XCTAssertEqual(stored.summary, "Original summary")
        XCTAssertTrue(stored.failureReason?.contains("Deepgram transcription failed") == true)
    }

    func testCanStartAfterPriorFailure() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        var failOnce = true
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in
                if failOnce {
                    failOnce = false
                    throw TranscriptionError.invalidResponse
                }
                return [TranscriptSegment(startTime: 0, endTime: 1, text: "x")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .failed)

        try await session.start()
        XCTAssertEqual(session.statusSnapshot, .recording)
    }

    func testStartWhileActiveThrowsAlreadyActive() async throws {
        let recorder = MockRecorder()
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [] },
            transcribe: { _, _, _ in [] },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        do {
            try await session.start()
            XCTFail("expected alreadyActive")
        } catch MeetingTranscriptionSession.SessionError.alreadyActive {
            // ok
        }
    }

    func testAudioRetainedTrueKeepsAudio() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { "sk-test" },
            retainAudio: { true },
            preflight: { .success(()) }
        )
        try await session.start()
        let id = session.activeSessionID!
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFile(id: id).path))
    }

    func testInterleavesSystemAndMicSegmentsByStartTime() async throws {
        let systemRecorder = MockRecorder()
        let micRecorder = MockRecorder()
        let systemChunk = tempRoot.appendingPathComponent("sys.m4a")
        let micChunk = tempRoot.appendingPathComponent("mic.m4a")
        try Data([0]).write(to: systemChunk)
        try Data([0]).write(to: micChunk)

        let session = MeetingTranscriptionSession(
            store: store,
            recorder: systemRecorder,
            micRecorder: micRecorder,
            chunker: { input, _ in
                if input.lastPathComponent.contains("audio.m4a") { return [systemChunk] }
                if input.lastPathComponent.contains("mic.m4a") { return [micChunk] }
                return []
            },
            transcribe: { url, _, source in
                if url == systemChunk {
                    return [
                        TranscriptSegment(startTime: 1.0, endTime: 2.0, text: "remote first", source: source),
                        TranscriptSegment(startTime: 5.0, endTime: 6.0, text: "remote later", source: source),
                    ]
                }
                if url == micChunk {
                    return [
                        TranscriptSegment(startTime: 3.0, endTime: 4.0, text: "local middle", source: source),
                    ]
                }
                return []
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )

        try await session.start()
        try await session.stop()
        await session.waitForCompletion()

        XCTAssertEqual(session.statusSnapshot, .completed)
        let id = session.activeSessionID!
        let stored = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(stored.segments.count, 3)
        XCTAssertEqual(stored.segments.map(\.text), ["remote first", "local middle", "remote later"])
        XCTAssertEqual(stored.segments.map(\.source), [.remote, .local, .remote])
    }

    func testMicFailureFallsBackToSystemOnly() async throws {
        let systemRecorder = MockRecorder()
        let micRecorder = FailingMicRecorder()
        let systemChunk = tempRoot.appendingPathComponent("sys.m4a")
        try Data([0]).write(to: systemChunk)

        let session = MeetingTranscriptionSession(
            store: store,
            recorder: systemRecorder,
            micRecorder: micRecorder,
            chunker: { _, _ in [systemChunk] },
            transcribe: { _, _, source in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "ok", source: source)]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )

        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
        let id = session.activeSessionID!
        let stored = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(stored.segments.count, 1)
        XCTAssertEqual(stored.segments[0].source, .remote)
    }

    final class FailingMicRecorder: MeetingAudioRecording {
        func start(outputURL: URL) async throws {
            throw MeetingMicCaptureError.permissionDenied
        }
        func stop() async throws -> URL {
            throw MeetingMicCaptureError.notRecording
        }
    }

    /// Recorder whose start throws — simulates a TCC drop or device-busy
    /// failure mid-launch.
    final class StartFailRecorder: MeetingAudioRecording {
        struct BoomError: Error {}
        func start(outputURL: URL) async throws { throw BoomError() }
        func stop() async throws -> URL {
            throw MeetingAudioCaptureError.notRecording
        }
    }

    /// Recorder whose stop throws — simulates a stream-shutdown failure.
    final class StopFailRecorder: MeetingAudioRecording {
        struct BoomError: Error {}
        var output: URL?
        func start(outputURL: URL) async throws {
            try Data([0]).write(to: outputURL)
            output = outputURL
        }
        func stop() async throws -> URL { throw BoomError() }
    }

    func testFailedStartClearsSessionAndAllowsRetry() async throws {
        // P1.3 regression: pre-fix, a failed system.start() left the
        // session pinned at .recording in memory and on disk; subsequent
        // start() threw .alreadyActive until app relaunch.
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: StartFailRecorder(),
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )

        do {
            try await session.start()
            XCTFail("Expected start to throw")
        } catch {
            // Expected. State should now be cleared.
        }
        XCTAssertNil(session.activeSessionID,
                     "After a failed start, no in-memory session should remain.")
        XCTAssertFalse(session.isActive,
                       "isActive must report false so the next start() isn't blocked.")
    }

    func testInitialPersistenceFailureClearsSessionAndAllowsRetry() async throws {
        struct PersistenceFailure: Error {}

        let recorder = MockRecorder()
        let transcriptStore = try XCTUnwrap(store)
        var failNextSave = true
        let session = MeetingTranscriptionSession(
            store: transcriptStore,
            recorder: recorder,
            chunker: { _, _ in [] },
            transcribe: { _, _, _ in [] },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) },
            saveSession: { candidate in
                if failNextSave {
                    failNextSave = false
                    throw PersistenceFailure()
                }
                try transcriptStore.save(candidate)
            }
        )

        do {
            try await session.start()
            XCTFail("Expected the initial persistence write to fail")
        } catch is PersistenceFailure {
            // Expected.
        }
        XCTAssertNil(session.activeSessionID)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(recorder.startCallCount, 0)

        try await session.start()
        XCTAssertEqual(session.statusSnapshot, .recording)
        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func testTranscriptDropDiagnosticReportsMetricsWithoutContent() {
        let transcript = "Project Nightingale launches Friday"

        let diagnostic = MeetingTranscriptionSession.redactedDropDiagnostic(
            reason: .cascade,
            source: .local,
            startTime: 12.5,
            endTime: 19.25,
            runLength: 7,
            text: transcript
        )

        XCTAssertTrue(diagnostic.contains("cascade"))
        XCTAssertTrue(diagnostic.contains("local"))
        XCTAssertTrue(diagnostic.contains("12.5-19.25s"))
        XCTAssertTrue(diagnostic.contains("run=7"))
        XCTAssertTrue(diagnostic.contains("chars=\(transcript.count)"))
        XCTAssertTrue(diagnostic.contains("words=4"))
        XCTAssertFalse(diagnostic.contains(transcript))
        XCTAssertFalse(diagnostic.contains("Nightingale"))
    }

    func testFailedStopClearsSessionAndAllowsRetry() async throws {
        // P1.4 regression: a system.stop() throw must not leave the session
        // pinned at .chunking forever.
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: StopFailRecorder(),
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) }
        )
        try await session.start()
        do {
            try await session.stop()
            XCTFail("Expected stop to throw")
        } catch {
            // Expected.
        }
        XCTAssertNil(session.activeSessionID)
        XCTAssertFalse(session.isActive)
    }

    func testChunkingPersistenceFailureStillStopsRecorderAndRecovers() async throws {
        struct PersistenceFailure: Error {}

        let recorder = MockRecorder()
        let chunkURL = tempRoot.appendingPathComponent("chunk-after-save-failure.m4a")
        try Data([0]).write(to: chunkURL)
        let transcriptStore = try XCTUnwrap(store)
        let session = MeetingTranscriptionSession(
            store: transcriptStore,
            recorder: recorder,
            chunker: { _, _ in [chunkURL] },
            transcribe: { _, _, _ in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            preflight: { .success(()) },
            saveSession: { candidate in
                if candidate.status == .chunking {
                    throw PersistenceFailure()
                }
                try transcriptStore.save(candidate)
            }
        )

        try await session.start()
        try await session.stop()

        XCTAssertEqual(recorder.stopCallCount, 1)
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
        let completedID = try XCTUnwrap(session.activeSessionID)
        XCTAssertEqual(transcriptStore.load(id: completedID)?.segments.map(\.text), ["recovered"])

        try await session.start()
        XCTAssertEqual(session.statusSnapshot, .recording)
    }

    func testPreflightFailureBlocksStart() async throws {
        // P1.1 regression: any entry point — including the floating HUD —
        // must run the preflight gate. A blocked preflight throws and
        // never touches the recorder.
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: MockRecorder(),
            chunker: { _, _ in [url] },
            transcribe: { _, _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { nil },
            retainAudio: { false },
            preflight: { .failure(.missingAPIKey) }
        )
        do {
            try await session.start()
            XCTFail("Preflight failure must block start")
        } catch let MeetingTranscriptionSession.SessionError.preflight(err) {
            XCTAssertEqual(err, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultPreflightUsesOnlyDeepgramKeyForDeepgramProvider() async throws {
        let savedMode = AppSettings.meetingModeEnabled
        let savedConsent = AppSettings.meetingConsentAcknowledged
        let savedBackendStatus = MeetingPreflight.backendStatusProvider
        defer {
            AppSettings.meetingModeEnabled = savedMode
            AppSettings.meetingConsentAcknowledged = savedConsent
            MeetingPreflight.backendStatusProvider = savedBackendStatus
        }
        AppSettings.meetingModeEnabled = true
        AppSettings.meetingConsentAcknowledged = true
        MeetingPreflight.backendStatusProvider = {
            MeetingBackendStatus(available: true, detail: "ready")
        }

        let session = MeetingTranscriptionSession(
            store: store,
            recorder: MockRecorder(),
            chunker: { _, _ in [] },
            transcribe: { _, _, _ in [] },
            provider: { .deepgram },
            apiKey: { nil },
            deepgramAPIKey: { "dg-test" },
            retainAudio: { false }
        )

        try await session.start()

        XCTAssertEqual(session.statusSnapshot, .recording)

        let missingDeepgramKey = MeetingTranscriptionSession(
            store: store,
            recorder: MockRecorder(),
            chunker: { _, _ in [] },
            transcribe: { _, _, _ in [] },
            provider: { .deepgram },
            apiKey: { "sk-openai-only" },
            deepgramAPIKey: { nil },
            retainAudio: { false }
        )
        do {
            try await missingDeepgramKey.start()
            XCTFail("An OpenAI key must not satisfy Deepgram preflight")
        } catch let MeetingTranscriptionSession.SessionError.preflight(error) {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// Minimal async semaphore for deterministic interleaving tests.
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(initial: Int) { self.value = initial }
    func signal() {
        if let w = waiters.first {
            waiters.removeFirst()
            w.resume()
        } else {
            value += 1
        }
    }
    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { c in waiters.append(c) }
    }
}

actor AtomicInt {
    private(set) var value: Int = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
