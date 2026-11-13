import XCTest
@testable import vox

final class DeepgramMeetingReliabilityTests: XCTestCase {
    private var root: URL!
    private var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vox-deepgram-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testTransientRateLimitRetriesAndCompletes() async throws {
        let attempts = AtomicInt()
        let session = MeetingTranscriptionSession(
            store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [] }, transcribe: { _, _, _ in XCTFail("Wrong provider"); return [] },
            deepgramTranscribe: { _ in
                let n = await attempts.increment()
                if n == 1 { throw DeepgramError.httpError(429, "limited") }
                return [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
            }, provider: { .deepgram }, apiKey: { nil }, deepgramAPIKey: { "test" },
            preflight: { .success(()) }, backoffSchedule: [0.001]
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
        let count = await attempts.value
        XCTAssertEqual(count, 2)
        let saved = try XCTUnwrap(store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertEqual(saved.segments.map(\.text), ["recovered"])
    }

    func testTransientTransportAndServerErrorsRetry() async throws {
        for failure in [DeepgramError.transportError(URLError(.networkConnectionLost)), .httpError(503, "unavailable")] {
            let attempts = AtomicInt()
            let session = MeetingTranscriptionSession(
                store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
                chunker: { _, _ in [] }, transcribe: { _, _, _ in [] },
                deepgramTranscribe: { _ in
                    let n = await attempts.increment()
                    if n == 1 { throw failure }
                    return [TranscriptSegment(startTime: 0, endTime: 1, text: "recovered")]
                }, provider: { .deepgram }, apiKey: { nil }, deepgramAPIKey: { "test" },
                preflight: { .success(()) }, backoffSchedule: [0.001]
            )
            try await session.start()
            try await session.stop()
            await session.waitForCompletion()
            XCTAssertEqual(session.statusSnapshot, .completed)
            let count = await attempts.value
            XCTAssertEqual(count, 2)
        }
    }

    func testLaterSourceFailurePreservesEarlierTranscript() async throws {
        let attempts = AtomicInt()
        let session = MeetingTranscriptionSession(
            store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            micRecorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [] }, transcribe: { _, _, _ in [] },
            deepgramTranscribe: { _ in
                let n = await attempts.increment()
                if n == 2 { throw DeepgramError.httpError(401, "unauthorized") }
                return [TranscriptSegment(startTime: 0, endTime: 1, text: "first source")]
            }, provider: { .deepgram }, apiKey: { nil }, deepgramAPIKey: { "test" },
            preflight: { .success(()) }, backoffSchedule: [0.001]
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        let saved = try XCTUnwrap(store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.segments.map(\.text), ["first source"])
        let count = await attempts.value
        XCTAssertEqual(count, 2, "Authentication failures should not be retried")
    }

    func testCancelDuringDeepgramUploadReportsCancelledAndPreservesPartialTranscript() async throws {
        let attempts = AtomicInt()
        let started = AsyncSemaphore(initial: 0)
        let session = MeetingTranscriptionSession(
            store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            micRecorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [] }, transcribe: { _, _, _ in [] },
            deepgramTranscribe: { _ in
                let n = await attempts.increment()
                if n == 2 {
                    await started.signal()
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                    catch { throw DeepgramError.transportError(error) }
                }
                return [TranscriptSegment(startTime: 0, endTime: 1, text: "first source")]
            }, provider: { .deepgram }, apiKey: { nil }, deepgramAPIKey: { "test" },
            preflight: { .success(()) }, backoffSchedule: [0.001]
        )
        try await session.start()
        try await session.stop()
        await started.wait()
        session.cancel()
        await session.waitForCompletion()
        let saved = try XCTUnwrap(store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertEqual(saved.status, .cancelled)
        XCTAssertEqual(saved.segments.map(\.text), ["first source"])
    }
}
