import XCTest
@testable import vox

final class MeetingRetryBudgetTests: XCTestCase {
    func testRetryDeadlineCancelsSlowRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        let chunk = root.appendingPathComponent("fixture.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0]).write(to: chunk)
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] }, transcribe: { _, _, _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return []
            }, apiKey: { "test" }, preflight: { .success(()) }, backoffSchedule: [0.01], retryBudget: 0.1)
        try await session.start()
        let start = ProcessInfo.processInfo.systemUptime
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertEqual(session.statusSnapshot, .failed)
    }

    func testRetryAfterBeyondBudgetFailsWithoutRetryingEarly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        let chunk = root.appendingPathComponent("fixture.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0]).write(to: chunk)
        let attempts = AtomicInt()
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] }, transcribe: { _, _, _ in [] },
            openrouterTranscribe: { _, _, _ in
                _ = await attempts.increment()
                throw OpenRouterMeetingError.rateLimited(retryAfter: 10)
            }, provider: { .openrouter }, apiKey: { nil }, openrouterAPIKey: { "test" },
            preflight: { .success(()) }, backoffSchedule: [0.001], retryBudget: 0.5)
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .failed)
        let count = await attempts.value
        XCTAssertEqual(count, 1)
        let saved = try XCTUnwrap(store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertTrue(saved.failureReason?.contains("429") ?? false)
    }

    func testOpenAIRateLimitIsRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) })
        let chunk = root.appendingPathComponent("fixture.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0]).write(to: chunk)
        let attempts = AtomicInt()
        let session = MeetingTranscriptionSession(store: store, recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] }, transcribe: { _, _, _ in
                if await attempts.increment() == 1 { throw TranscriptionError.httpError(429, "limited") }
                return [TranscriptSegment(startTime: 0, endTime: 1, text: "success")]
            }, apiKey: { "test" }, preflight: { .success(()) }, backoffSchedule: [0.001], retryBudget: 1)
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        XCTAssertEqual(session.statusSnapshot, .completed)
        let count = await attempts.value
        XCTAssertEqual(count, 2)
    }
}
