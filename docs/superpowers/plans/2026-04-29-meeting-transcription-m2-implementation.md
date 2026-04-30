# Meeting Transcription M2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the M2 meeting-transcription pipeline (record system audio via ScreenCaptureKit, end-of-meeting chunked Whisper transcription, persisted timestamped transcripts, dedicated transcripts window) on top of the M1 scaffolding (commit `12d508e`), without regressing the existing dictation flow.

**Architecture:** Five new units (`MeetingAudioCapture`, `MeetingTranscriptionSession`, `MeetingTranscriptStore`, `MeetingChunker`, `MeetingTranscriptsWindow`) plus an additive `OpenAITranscriber.transcribeMeetingChunk(...)` method. Dictation code paths remain unchanged except for a non-invasive Fn-hold mutex check and a new menu item. Per-chunk failures retry forever with backoff until user cancellation; the dictation hotkey is hard-disabled while a meeting is recording.

**Tech Stack:** Swift 5.9+, AppKit + SwiftUI, ScreenCaptureKit (macOS 13+), AVFoundation (`AVAssetExportSession`, `AVAssetWriter`), `URLSession` for OpenAI Whisper API, `XCTest` with custom `URLProtocol` stub for HTTP mocking.

**Spec:** `docs/superpowers/specs/2026-04-29-meeting-transcription-m2-design.md`

**M1 baseline (do not disturb):** suite at 221 tests, `DictationRegressionTests` baseline `failure_rate=0.0`, `quality_score=1.0`, `latency=4ms`. After M2: ~241 tests, dictation baseline unchanged.

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `Sources/vox/Util/MeetingTranscriptStore.swift` | `TranscriptSegment`, `TranscriptSession`, `MeetingTranscriptStore` (CRUD + cold-recovery sweep) |
| `Sources/vox/STT/MeetingChunker.swift` | Pure helper: split a finalized .m4a into 5-min m4a chunks via `AVAssetExportSession` |
| `Sources/vox/Meeting/MeetingAudioCapture.swift` | `SCStream` wrapper, encodes to AAC m4a via `AVAssetWriter`. Hidden behind `MeetingAudioRecording` protocol for testability |
| `Sources/vox/STT/MeetingTranscriptionSession.swift` | Singleton state machine: record → chunk → upload → persist; serial upload with infinite retry/backoff |
| `Sources/vox/App/MeetingTranscriptsWindow.swift` | Lazy `NSWindow` + SwiftUI host: sidebar list + detail pane + export/delete |
| `Tests/voxTests/MeetingTranscriptStoreTests.swift` | Codable round-trip, list ordering, delete, `purgeAudio`, atomic writes, cold-recovery |
| `Tests/voxTests/MeetingChunkerTests.swift` | Fixture m4a → expected chunk count and durations |
| `Tests/voxTests/OpenAITranscriberMeetingTests.swift` | `transcribeMeetingChunk` with `URLProtocolStub` returning canned `verbose_json`; verifies offset stitching |
| `Tests/voxTests/MeetingTranscriptionSessionTests.swift` | Mock recorder + mock transcriber: happy path, transient retry, infinite-retry holds, user cancel, audio-retain-off |
| `Tests/voxTests/MeetingMutexTests.swift` | Fn-hold path early-returns when `MeetingTranscriptionSession.shared.isRecording == true` |
| `Tests/voxTests/Support/URLProtocolStub.swift` | Reusable test stub registered on `URLSessionConfiguration.ephemeral` |

### Modified files (additive only)

| Path | Change |
|------|--------|
| `Sources/vox/Util/AppSettings.swift` | Add `meetingRetainAudio: Bool = false` |
| `Sources/vox/STT/OpenAITranscriber.swift` | Add `transcribeMeetingChunk(...)` static method (existing `transcribe(...)` and `sendWithRetry(...)` untouched) |
| `Sources/vox/Meeting/MeetingPreflight.swift` | Replace `backendStatusProvider` default with live `CGPreflightScreenCaptureAccess()` check; new `MeetingGateError` cases |
| `Sources/vox/App/MenuBarController.swift` | New "Show Meeting Transcripts…" item; wire `stopMeetingTranscript` to session; gate Start on dictation-active |
| `Sources/vox/App/SettingsWindow.swift` | New "Keep audio after transcription" toggle in Meeting (Beta) section |
| `Sources/vox/Audio/AudioRecorder.swift` | Promote `isRecording` to `public var` so `KeyboardController` can read it (or expose via existing accessor — choose minimal change) |
| `Sources/vox/Audio/KeyboardController.swift` | Mutex check at top of Fn-down handler |

---

## Task 0: Pre-flight verification (no code changes)

- [ ] **Step 1: Confirm starting state**

Run:
```bash
git status
swift test 2>&1 | tail -3
```

Expected: clean working tree on `main`. Test count: `Executed 221 tests, with 0 failures`. If either fails, stop and fix before proceeding.

- [ ] **Step 2: Confirm dictation regression baseline**

Run:
```bash
./scripts/run-dictation-regression.sh
```

Expected: `failure_rate=0.0 quality_score=1.0 latency_ms=4` (or whatever is currently logged as the baseline — capture it for comparison at end of plan).

- [ ] **Step 3: Read the spec**

Read `docs/superpowers/specs/2026-04-29-meeting-transcription-m2-design.md` end-to-end. Confirm all 15 locked decisions in the table are still acceptable. If any are not, raise to user before writing code.

---

## Task 1: URL protocol stub for HTTP mocking (test infra)

**Files:**
- Create: `Tests/voxTests/Support/URLProtocolStub.swift`

- [ ] **Step 1: Write the stub**

Create `Tests/voxTests/Support/URLProtocolStub.swift`:

```swift
import Foundation

/// Test-only URLProtocol that returns canned responses without hitting the network.
/// Register on a per-test `URLSessionConfiguration.ephemeral` so it does not leak globally.
final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Set per-test before instantiating a URLSession with this protocol class registered.
    static var handler: Handler?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolStub.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Build**

Run:
```bash
swift build 2>&1 | tail -5
```

Expected: clean build (no usage yet — file just compiles).

- [ ] **Step 3: Commit**

```bash
git add Tests/voxTests/Support/URLProtocolStub.swift
git commit --no-gpg-sign -m "test: add URLProtocolStub for HTTP mocking"
```

---

## Task 2: TranscriptSession + TranscriptSegment data model

**Files:**
- Create: `Sources/vox/Util/MeetingTranscriptStore.swift`
- Create: `Tests/voxTests/MeetingTranscriptStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/voxTests/MeetingTranscriptStoreTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to confirm failure**

Run:
```bash
swift test --filter MeetingTranscriptStoreTests 2>&1 | tail -20
```

Expected: compilation failure (`MeetingTranscriptStore`, `TranscriptSession`, `TranscriptSegment` undefined).

- [ ] **Step 3: Write the implementation**

Create `Sources/vox/Util/MeetingTranscriptStore.swift`:

```swift
import Foundation

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let text: String

    public init(startTime: Double, endTime: Double, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct TranscriptSession: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case recording, chunking, transcribing, completed, cancelled, failed
    }

    public let id: UUID
    public var title: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: Status
    public var chunksTotal: Int
    public var chunksCompleted: Int
    public var segments: [TranscriptSegment]
    public var audioRetained: Bool

    public init(
        id: UUID,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        status: Status,
        chunksTotal: Int,
        chunksCompleted: Int,
        segments: [TranscriptSegment],
        audioRetained: Bool
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.chunksTotal = chunksTotal
        self.chunksCompleted = chunksCompleted
        self.segments = segments
        self.audioRetained = audioRetained
    }
}

public extension Notification.Name {
    static let meetingTranscriptStoreDidChange =
        Notification.Name("vox.meetingTranscriptStoreDidChange")
}

public final class MeetingTranscriptStore {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default location: ~/Library/Application Support/Vox/MeetingTranscripts
    public static func defaultRoot() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("MeetingTranscripts", isDirectory: true)
    }

    public init(rootDirectory: URL = MeetingTranscriptStore.defaultRoot()) {
        self.rootDirectory = rootDirectory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func sessionDirectory(id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func audioFile(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("audio.m4a")
    }

    public func chunksDirectory(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("chunks", isDirectory: true)
    }

    private func transcriptFile(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("transcript.json")
    }

    public func save(_ session: TranscriptSession) throws {
        let dir = sessionDirectory(id: session.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: transcriptFile(id: session.id), options: .atomic)
        NotificationCenter.default.post(name: .meetingTranscriptStoreDidChange, object: nil)
    }

    public func load(id: UUID) -> TranscriptSession? {
        guard let data = try? Data(contentsOf: transcriptFile(id: id)) else { return nil }
        return try? decoder.decode(TranscriptSession.self, from: data)
    }

    public func list() -> [TranscriptSession] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        let sessions = entries.compactMap { dir -> TranscriptSession? in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            return load(id: id)
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: sessionDirectory(id: id))
        NotificationCenter.default.post(name: .meetingTranscriptStoreDidChange, object: nil)
    }

    public func purgeAudio(for id: UUID) throws {
        let url = audioFile(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        if var session = load(id: id) {
            session.audioRetained = false
            try save(session)
        }
    }

    /// Cold-recovery sweep: any session left in an in-flight state from a prior process
    /// (recording, chunking, transcribing) is reset to `.failed` so the UI shows a clean
    /// terminal state rather than a stuck spinner. Idempotent.
    public func recoverInFlightSessions() {
        for var session in list() {
            switch session.status {
            case .recording, .chunking, .transcribing:
                session.status = .failed
                if session.endedAt == nil { session.endedAt = Date() }
                try? save(session)
            case .completed, .cancelled, .failed:
                break
            }
        }
    }
}
```

- [ ] **Step 4: Run test to confirm pass**

Run:
```bash
swift test --filter MeetingTranscriptStoreTests 2>&1 | tail -10
```

Expected: `Test Suite 'MeetingTranscriptStoreTests' passed`.

- [ ] **Step 5: Add the rest of the store tests**

Append to `Tests/voxTests/MeetingTranscriptStoreTests.swift`:

```swift
extension MeetingTranscriptStoreTests {
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
        var s = makeSession(audioRetained: true)
        try store.save(s)
        // Simulate audio file present.
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
```

- [ ] **Step 6: Run all store tests**

Run:
```bash
swift test --filter MeetingTranscriptStoreTests 2>&1 | tail -15
```

Expected: 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/vox/Util/MeetingTranscriptStore.swift Tests/voxTests/MeetingTranscriptStoreTests.swift
git commit --no-gpg-sign -m "feat(meeting): TranscriptSession model + MeetingTranscriptStore (M2)"
```

---

## Task 3: AppSettings.meetingRetainAudio + SettingsWindow toggle

**Files:**
- Modify: `Sources/vox/Util/AppSettings.swift` (add key + computed var alongside existing meeting keys)
- Modify: `Sources/vox/App/SettingsWindow.swift` (add toggle inside the existing "Meeting Transcription (Beta)" section)
- Test: covered indirectly by reading AppSettings; no dedicated unit test (M1 pattern: settings are not unit-tested individually).

- [ ] **Step 1: Add the settings key**

Edit `Sources/vox/Util/AppSettings.swift`. After the existing `private static let meetingBackendKey = "meetingCaptureBackend"` line (around line 68), add:

```swift
    private static let meetingRetainAudioKey = "meetingRetainAudio"
```

After the existing `meetingCaptureBackend` computed property (around line 127), add:

```swift
    static var meetingRetainAudio: Bool {
        get { UserDefaults.standard.bool(forKey: meetingRetainAudioKey) }
        set { UserDefaults.standard.set(newValue, forKey: meetingRetainAudioKey) }
    }
```

- [ ] **Step 2: Add the toggle to SettingsWindow**

Open `Sources/vox/App/SettingsWindow.swift`. Locate the "Meeting Transcription (Beta)" section (added in M1; search for `Meeting Transcription`). Inside that section, after the existing consent toggle row, add a new toggle bound to `AppSettings.meetingRetainAudio`. Match the existing M1 toggle wiring style (NSButton.checkbox with target/action, or SwiftUI `Toggle` — whichever pattern the surrounding code uses).

Example (NSButton-style — adapt to whatever the surrounding M1 code uses):

```swift
let retainAudioToggle = NSButton(
    checkboxWithTitle: "Keep audio recording after transcription (uses extra disk)",
    target: self,
    action: #selector(toggleMeetingRetainAudio(_:))
)
retainAudioToggle.state = AppSettings.meetingRetainAudio ? .on : .off
// Add to the Meeting Transcription stack view immediately under the consent row.
```

And add the matching action method nearby:

```swift
@objc private func toggleMeetingRetainAudio(_ sender: NSButton) {
    AppSettings.meetingRetainAudio = (sender.state == .on)
}
```

- [ ] **Step 3: Build**

Run:
```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 4: Run full suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 227 tests, 0 failures (221 prior + 6 new from Task 2).

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Util/AppSettings.swift Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "feat(meeting): meetingRetainAudio setting + Settings toggle (M2)"
```

---

## Task 4: OpenAITranscriber.transcribeMeetingChunk + offset stitching

**Files:**
- Modify: `Sources/vox/STT/OpenAITranscriber.swift` (additive method only; existing `transcribe(...)` and `sendWithRetry(...)` not modified)
- Create: `Tests/voxTests/OpenAITranscriberMeetingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/voxTests/OpenAITranscriberMeetingTests.swift`:

```swift
import XCTest
@testable import vox

final class OpenAITranscriberMeetingTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private func writeFixtureAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: url)
        return url
    }

    func testTranscribeMeetingChunkAppliesOffsetAndDecodesSegments() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {
              "task": "transcribe",
              "language": "en",
              "duration": 12.0,
              "text": "hello world",
              "segments": [
                {"id": 0, "start": 0.0, "end": 4.5, "text": "hello"},
                {"id": 1, "start": 4.5, "end": 12.0, "text": "world"}
              ]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()

        let segments = try await OpenAITranscriber.transcribeMeetingChunk(
            fileURL: fixture,
            offsetSeconds: 600.0,
            apiKey: "sk-test",
            urlSession: session
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].startTime, 600.0, accuracy: 0.001)
        XCTAssertEqual(segments[0].endTime, 604.5, accuracy: 0.001)
        XCTAssertEqual(segments[0].text, "hello")
        XCTAssertEqual(segments[1].startTime, 604.5, accuracy: 0.001)
        XCTAssertEqual(segments[1].endTime, 612.0, accuracy: 0.001)
    }

    func testTranscribeMeetingChunkThrowsOnHTTPError() async throws {
        URLProtocolStub.handler = { _ in
            let body = "{\"error\":\"unauthorized\"}".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()

        do {
            _ = try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: fixture, offsetSeconds: 0, apiKey: "sk-test", urlSession: session
            )
            XCTFail("Expected throw")
        } catch let TranscriptionError.httpError(code, _) {
            XCTAssertEqual(code, 401)
        }
    }

    func testTranscribeMeetingChunkOffsetZeroIdentity() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {"segments": [{"id":0,"start":1.0,"end":2.0,"text":"x"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()
        let segs = try await OpenAITranscriber.transcribeMeetingChunk(
            fileURL: fixture, offsetSeconds: 0, apiKey: "sk-test", urlSession: session
        )
        XCTAssertEqual(segs[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(segs[0].endTime, 2.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to confirm failure**

Run:
```bash
swift test --filter OpenAITranscriberMeetingTests 2>&1 | tail -10
```

Expected: compilation failure (`transcribeMeetingChunk` undefined).

- [ ] **Step 3: Add the method**

Open `Sources/vox/STT/OpenAITranscriber.swift`. At the bottom of the file (after the closing brace of `OpenAITranscriber` struct, line 105), add a new extension:

```swift
extension OpenAITranscriber {
    private struct WhisperVerboseResponse: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        let segments: [Segment]
    }

    /// Transcribe one meeting audio chunk via Whisper `verbose_json` and stitch each
    /// segment's start/end onto an absolute meeting timeline using `offsetSeconds`.
    ///
    /// Caller (`MeetingTranscriptionSession`) is responsible for the outer infinite-retry
    /// loop. This method only retries the same transient transport errors that dictation
    /// retries via `sendWithRetry`, then surfaces the underlying error.
    public static func transcribeMeetingChunk(
        fileURL: URL,
        offsetSeconds: Double,
        apiKey: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        urlSession: URLSession = .shared
    ) async throws -> [TranscriptSegment] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        let audioData = try Data(contentsOf: fileURL)
        let boundary = "vox-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMeetingBody(
            boundary: boundary,
            audio: audioData,
            filename: fileURL.lastPathComponent
        )
        request.timeoutInterval = 120.0

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await sendWithRetry(request, session: urlSession)
        } catch {
            throw TranscriptionError.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError(http.statusCode, body)
        }

        let decoded: WhisperVerboseResponse
        do {
            decoded = try JSONDecoder().decode(WhisperVerboseResponse.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }

        return decoded.segments.map { seg in
            TranscriptSegment(
                startTime: seg.start + offsetSeconds,
                endTime: seg.end + offsetSeconds,
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func buildMeetingBody(boundary: String, audio: Data, filename: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-1")
        field("response_format", "verbose_json")
        field("timestamp_granularities[]", "segment")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
```

- [ ] **Step 4: Update `sendWithRetry` to accept a session parameter**

The existing `sendWithRetry` (lines 64-81 of `OpenAITranscriber.swift`) hard-codes `URLSession.shared`. To preserve the dictation behavior and allow the new chunk method to inject a stub session, change its signature additively. Open the file and edit lines 64-81 to:

```swift
    private static func sendWithRetry(
        _ request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        let retriable: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .dnsLookupFailed,
            .notConnectedToInternet, .cannotConnectToHost
        ]
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await session.data(for: request)
            } catch let urlError as URLError where retriable.contains(urlError.code) {
                lastError = urlError
                if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.timedOut)
    }
```

The default-argument preserves the existing dictation call site (line 50, `try await Self.sendWithRetry(request)`) — no change needed there.

Also change `private static func sendWithRetry` to `internal static func sendWithRetry` so the extension can call it from the same file (it already can, since they're in the same module). Leave it `private` if Swift accepts the cross-extension same-file access; verify by building. If build fails, change `private static` to `static` (file-private is fine across extensions in the same file).

- [ ] **Step 5: Run test to confirm pass**

Run:
```bash
swift test --filter OpenAITranscriberMeetingTests 2>&1 | tail -15
```

Expected: 3 tests pass.

- [ ] **Step 6: Run full suite (regression check)**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 230 tests, 0 failures (227 prior + 3 new). Dictation tests must still pass — confirms `sendWithRetry` change is backwards-compatible.

- [ ] **Step 7: Commit**

```bash
git add Sources/vox/STT/OpenAITranscriber.swift Tests/voxTests/OpenAITranscriberMeetingTests.swift
git commit --no-gpg-sign -m "feat(meeting): OpenAITranscriber.transcribeMeetingChunk with verbose_json (M2)"
```

---

## Task 5: MeetingChunker

**Files:**
- Create: `Sources/vox/STT/MeetingChunker.swift`
- Create: `Tests/voxTests/MeetingChunkerTests.swift`

The chunker splits a finalized .m4a into 5-minute AAC m4a segments via `AVAssetExportSession`. Pure logic — no UI, no app state.

- [ ] **Step 1: Write the failing test**

Create `Tests/voxTests/MeetingChunkerTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import vox

final class MeetingChunkerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-chunker-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Generate a silent AAC m4a of the requested duration for chunker tests.
    /// Uses AVAssetWriter with kAudioFormatMPEG4AAC at 16 kHz mono.
    private func generateSilentM4A(durationSeconds: Double) async throws -> URL {
        let url = tempDir.appendingPathComponent("input.m4a")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let sampleRate: Int32 = 16000
        let totalSamples = Int(durationSeconds * Double(sampleRate))
        let bufferSamples = 1024
        var samplesWritten = 0
        while samplesWritten < totalSamples {
            let n = min(bufferSamples, totalSamples - samplesWritten)
            var bytes = [Int16](repeating: 0, count: n)
            let blockBuffer = try makeBlockBuffer(bytes: &bytes)
            var asbd = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate),
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
            )
            var formatDesc: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &asbd,
                layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                extensions: nil, formatDescriptionOut: &formatDesc
            )
            var sampleBuffer: CMSampleBuffer?
            let timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: sampleRate),
                presentationTimeStamp: CMTime(value: CMTimeValue(samplesWritten), timescale: sampleRate),
                decodeTimeStamp: .invalid
            )
            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
                makeDataReadyCallback: nil, refcon: nil,
                formatDescription: formatDesc, sampleCount: n,
                sampleTimingEntryCount: 1, sampleTimingArray: [timing],
                sampleSizeEntryCount: 1, sampleSizeArray: [2],
                sampleBufferOut: &sampleBuffer
            )
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            input.append(sampleBuffer!)
            samplesWritten += n
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    private func makeBlockBuffer(bytes: inout [Int16]) throws -> CMBlockBuffer {
        let byteCount = bytes.count * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount,
            flags: 0, blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let bb = blockBuffer else {
            throw NSError(domain: "test", code: -1)
        }
        bytes.withUnsafeMutableBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: bb,
                offsetIntoDestination: 0, dataLength: byteCount
            )
        }
        return bb
    }

    func testTwelveMinuteAudioProducesThreeChunks() async throws {
        let input = try await generateSilentM4A(durationSeconds: 720)  // 12 min
        let chunker = MeetingChunker(chunkDurationSeconds: 300)
        let outputDir = tempDir.appendingPathComponent("chunks")
        let chunks = try await chunker.split(input: input, outputDirectory: outputDir)

        XCTAssertEqual(chunks.count, 3)
        for url in chunks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        let asset0 = AVURLAsset(url: chunks[0])
        let asset2 = AVURLAsset(url: chunks[2])
        let dur0 = try await asset0.load(.duration).seconds
        let dur2 = try await asset2.load(.duration).seconds
        XCTAssertEqual(dur0, 300.0, accuracy: 1.0)
        XCTAssertEqual(dur2, 120.0, accuracy: 1.0)
    }

    func testShortAudioProducesSingleChunk() async throws {
        let input = try await generateSilentM4A(durationSeconds: 60)
        let chunker = MeetingChunker(chunkDurationSeconds: 300)
        let outputDir = tempDir.appendingPathComponent("chunks")
        let chunks = try await chunker.split(input: input, outputDirectory: outputDir)
        XCTAssertEqual(chunks.count, 1)
    }
}
```

- [ ] **Step 2: Run test to confirm failure**

Run:
```bash
swift test --filter MeetingChunkerTests 2>&1 | tail -10
```

Expected: compilation failure (`MeetingChunker` undefined).

- [ ] **Step 3: Write the implementation**

Create `Sources/vox/STT/MeetingChunker.swift`:

```swift
import AVFoundation
import Foundation

public enum MeetingChunkerError: Error, CustomStringConvertible {
    case exportFailed(Error?)
    case zeroDurationAsset
    case noAudioTrack

    public var description: String {
        switch self {
        case .exportFailed(let e):
            return "Chunk export failed: \(e?.localizedDescription ?? "unknown")"
        case .zeroDurationAsset:
            return "Source asset reported zero duration."
        case .noAudioTrack:
            return "Source asset has no audio track."
        }
    }
}

public struct MeetingChunker {
    public let chunkDurationSeconds: Double

    public init(chunkDurationSeconds: Double = 300) {
        self.chunkDurationSeconds = chunkDurationSeconds
    }

    /// Split `input` into ordered AAC m4a chunks of at most `chunkDurationSeconds`,
    /// written into `outputDirectory` as `000.m4a`, `001.m4a`, …
    /// Returns the chunk URLs in order.
    public func split(input: URL, outputDirectory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )

        let asset = AVURLAsset(url: input)
        let totalDuration = try await asset.load(.duration).seconds
        guard totalDuration > 0 else { throw MeetingChunkerError.zeroDurationAsset }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw MeetingChunkerError.noAudioTrack }

        let chunkCount = Int(ceil(totalDuration / chunkDurationSeconds))
        var outputs: [URL] = []
        for i in 0..<chunkCount {
            let start = Double(i) * chunkDurationSeconds
            let duration = min(chunkDurationSeconds, totalDuration - start)
            let outURL = outputDirectory.appendingPathComponent(
                String(format: "%03d.m4a", i)
            )
            try? FileManager.default.removeItem(at: outURL)
            try await exportSegment(
                asset: asset,
                start: start,
                duration: duration,
                outputURL: outURL
            )
            outputs.append(outURL)
        }
        return outputs
    }

    private func exportSegment(
        asset: AVAsset, start: Double, duration: Double, outputURL: URL
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MeetingChunkerError.exportFailed(nil)
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        let timescale: CMTimeScale = 600
        let startTime = CMTime(seconds: start, preferredTimescale: timescale)
        let durationTime = CMTime(seconds: duration, preferredTimescale: timescale)
        exporter.timeRange = CMTimeRange(start: startTime, duration: durationTime)

        await exporter.export()
        switch exporter.status {
        case .completed:
            return
        default:
            throw MeetingChunkerError.exportFailed(exporter.error)
        }
    }
}
```

- [ ] **Step 4: Run chunker tests**

Run:
```bash
swift test --filter MeetingChunkerTests 2>&1 | tail -15
```

Expected: 2 tests pass. (Generation of fixture m4a + chunking takes ~3-5 seconds.)

- [ ] **Step 5: Run full suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 232 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/vox/STT/MeetingChunker.swift Tests/voxTests/MeetingChunkerTests.swift
git commit --no-gpg-sign -m "feat(meeting): MeetingChunker splits .m4a into 5-min AAC segments (M2)"
```

---

## Task 6: MeetingAudioRecording protocol + MeetingAudioCapture (SCStream)

**Files:**
- Create: `Sources/vox/Meeting/MeetingAudioCapture.swift`
- No unit test (SCStream + permission gating cannot be exercised in `swift test` without a real Mac with TCC granted; covered by integration smoke in Task 11).

Defining the protocol up front lets `MeetingTranscriptionSession` (Task 7) take a mock recorder. The concrete `MeetingAudioCapture` is a thin wrapper.

- [ ] **Step 1: Write the protocol + implementation**

Create `Sources/vox/Meeting/MeetingAudioCapture.swift`:

```swift
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Test-substitutable interface for the meeting capture backend. Production wires
/// `MeetingAudioCapture`; tests inject a mock that writes a fixture m4a file.
public protocol MeetingAudioRecording: AnyObject {
    /// Begins recording system audio to `outputURL`. Throws on permission denial or
    /// stream start failure. Idempotent: calling start twice in a row is an error.
    func start(outputURL: URL) async throws

    /// Stops the in-flight recording, flushes the writer, and returns the file URL.
    /// If recording was never started, throws.
    func stop() async throws -> URL
}

public enum MeetingAudioCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case noShareableContent(Error)
    case streamStartFailed(Error)
    case writerFailed(Error)
    case notRecording

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission required (System Settings → Privacy & Security → Screen Recording)."
        case .noShareableContent(let e):
            return "Could not enumerate shareable content: \(e.localizedDescription)"
        case .streamStartFailed(let e):
            return "SCStream failed to start: \(e.localizedDescription)"
        case .writerFailed(let e):
            return "Audio writer failed: \(e.localizedDescription)"
        case .notRecording:
            return "stop() called without a prior start()."
        }
    }
}

@available(macOS 13.0, *)
public final class MeetingAudioCapture: NSObject, MeetingAudioRecording, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "vox.meeting.capture", qos: .userInitiated)
    private var sessionStarted = false

    public override init() { super.init() }

    public func start(outputURL: URL) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw MeetingAudioCaptureError.permissionDenied
        }
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.outputURL = outputURL

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw MeetingAudioCaptureError.noShareableContent(error)
        }
        guard let display = content.displays.first else {
            throw MeetingAudioCaptureError.noShareableContent(
                NSError(domain: "vox.meeting", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "no displays"])
            )
        }
        let excluded = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.writer = writer
        self.writerInput = input

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw MeetingAudioCaptureError.streamStartFailed(error)
        }
        self.stream = stream
    }

    public func stop() async throws -> URL {
        guard let stream = stream, let writer = writer,
              let input = writerInput, let outputURL = outputURL else {
            throw MeetingAudioCaptureError.notRecording
        }
        try? await stream.stopCapture()
        input.markAsFinished()
        await writer.finishWriting()
        let url = outputURL
        // Reset state so a second start() works.
        self.stream = nil
        self.writer = nil
        self.writerInput = nil
        self.outputURL = nil
        self.sessionStarted = false
        return url
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              let writer = writer,
              let input = writerInput,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if !sessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: clean build. If `ScreenCaptureKit` is not linked, add it to `Package.swift` `linkerSettings` (`.linkedFramework("ScreenCaptureKit")`) — vox builds against it implicitly via macOS 13+ target.

- [ ] **Step 3: Run full suite (no new tests, regression check)**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 232 tests, 0 failures (no new tests yet — capture is exercised manually).

- [ ] **Step 4: Commit**

```bash
git add Sources/vox/Meeting/MeetingAudioCapture.swift
git commit --no-gpg-sign -m "feat(meeting): MeetingAudioCapture (SCStream → AAC m4a) + protocol (M2)"
```

---

## Task 7: MeetingTranscriptionSession state machine

**Files:**
- Create: `Sources/vox/STT/MeetingTranscriptionSession.swift`
- Create: `Tests/voxTests/MeetingTranscriptionSessionTests.swift`

This is the largest task. The session orchestrates record → chunk → upload-with-retry → persist. Backed by injected `MeetingAudioRecording` + a transcribe closure so tests can mock both.

- [ ] **Step 1: Write the failing test**

Create `Tests/voxTests/MeetingTranscriptionSessionTests.swift`:

```swift
import XCTest
@testable import vox

final class MeetingTranscriptionSessionTests: XCTestCase {
    var tempRoot: URL!
    var store: MeetingTranscriptStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-session-\(UUID().uuidString)")
        store = MeetingTranscriptStore(rootDirectory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // Mock recorder: writes a stub .m4a (any bytes; chunker and transcriber are mocked).
    final class MockRecorder: MeetingAudioRecording {
        var startedAt: Date?
        var output: URL?
        func start(outputURL: URL) async throws {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0xFA, 0xCE]).write(to: outputURL)
            self.output = outputURL
            self.startedAt = Date()
        }
        func stop() async throws -> URL {
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
            transcribe: { url, offset in
                let i = chunkURLs.firstIndex(of: url)!
                return [TranscriptSegment(
                    startTime: offset, endTime: offset + 1.0,
                    text: "chunk \(i)"
                )]
            },
            apiKey: { "sk-test" },
            retainAudio: { false }
        )

        try await session.start()
        try await session.stop()

        // Wait until the upload loop completes.
        for _ in 0..<200 {
            if session.statusSnapshot == .completed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

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
        var attempts = 0
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [chunkURL] },
            transcribe: { _, offset in
                attempts += 1
                if attempts < 3 {
                    throw TranscriptionError.transportError(URLError(.timedOut))
                }
                return [TranscriptSegment(startTime: offset, endTime: offset + 1, text: "ok")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false },
            backoffSchedule: [0.01, 0.01, 0.01]
        )
        try await session.start()
        try await session.stop()
        for _ in 0..<200 {
            if session.statusSnapshot == .completed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(session.statusSnapshot, .completed)
        XCTAssertEqual(attempts, 3)
    }

    func testUserCancelMidUploadPreservesPartialSegments() async throws {
        let recorder = MockRecorder()
        let urls = (0..<5).map { tempRoot.appendingPathComponent("c-\($0).m4a") }
        for u in urls { try Data([0]).write(to: u) }
        let cancelAfter = AsyncSemaphore(initial: 0)
        var transcribeCount = 0
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in urls },
            transcribe: { url, offset in
                transcribeCount += 1
                if transcribeCount == 2 {
                    await cancelAfter.signal()
                    // Block long enough for cancel to land.
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    try Task.checkCancellation()
                }
                return [TranscriptSegment(startTime: offset, endTime: offset+1, text: "x")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false }
        )
        try await session.start()
        try await session.stop()
        await cancelAfter.wait()
        session.cancel()

        for _ in 0..<200 {
            if session.statusSnapshot == .cancelled { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
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
            transcribe: { _, _ in
                [TranscriptSegment(startTime: 0, endTime: 1, text: "x")]
            },
            apiKey: { "sk-test" },
            retainAudio: { false }
        )
        try await session.start()
        let id = session.activeSessionID!
        let audioPath = store.audioFile(id: id).path
        // Recorder writes its file to that audioPath.
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioPath))
        try await session.stop()
        for _ in 0..<200 {
            if session.statusSnapshot == .completed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioPath))
    }

    func testAudioRetainedTrueKeepsAudio() async throws {
        let recorder = MockRecorder()
        let url = tempRoot.appendingPathComponent("c.m4a")
        try Data([0]).write(to: url)
        let session = MeetingTranscriptionSession(
            store: store,
            recorder: recorder,
            chunker: { _, _ in [url] },
            transcribe: { _, _ in [TranscriptSegment(startTime: 0, endTime: 1, text: "x")] },
            apiKey: { "sk-test" },
            retainAudio: { true }
        )
        try await session.start()
        let id = session.activeSessionID!
        try await session.stop()
        for _ in 0..<200 {
            if session.statusSnapshot == .completed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFile(id: id).path))
    }
}

/// Minimal async semaphore for cancellation tests.
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
```

- [ ] **Step 2: Run test to confirm failure**

Run:
```bash
swift test --filter MeetingTranscriptionSessionTests 2>&1 | tail -10
```

Expected: compilation failure (`MeetingTranscriptionSession` undefined).

- [ ] **Step 3: Write the implementation**

Create `Sources/vox/STT/MeetingTranscriptionSession.swift`:

```swift
import Foundation

/// Coordinates a single end-to-end meeting capture: record audio, slice into chunks,
/// upload each chunk to Whisper with infinite-retry-on-transport-failure, persist segments.
/// Singleton via `.shared` for the app; tests instantiate directly with mocks.
public final class MeetingTranscriptionSession {
    public typealias Chunker = (URL, URL) async throws -> [URL]
    public typealias Transcribe = (URL, Double) async throws -> [TranscriptSegment]

    public static let shared = MeetingTranscriptionSession(
        store: MeetingTranscriptStore(),
        recorder: nil,
        chunker: { input, dir in
            try await MeetingChunker().split(input: input, outputDirectory: dir)
        },
        transcribe: { url, offset in
            let key = KeychainStore().read() ?? ""
            return try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: url, offsetSeconds: offset, apiKey: key
            )
        },
        apiKey: { KeychainStore().read() },
        retainAudio: { AppSettings.meetingRetainAudio }
    )

    private let store: MeetingTranscriptStore
    private let recorderFactory: () -> MeetingAudioRecording
    private let chunker: Chunker
    private let transcribe: Transcribe
    private let apiKeyProvider: () -> String?
    private let retainAudioProvider: () -> Bool
    private let backoffSchedule: [Double]
    private let chunkDuration: Double = 300

    private var recorder: MeetingAudioRecording?
    private var uploadTask: Task<Void, Never>?
    private let lock = NSLock()
    private var session: TranscriptSession?

    public var activeSessionID: UUID? {
        lock.lock(); defer { lock.unlock() }
        return session?.id
    }

    public var statusSnapshot: TranscriptSession.Status? {
        lock.lock(); defer { lock.unlock() }
        return session?.status
    }

    public var isRecording: Bool {
        statusSnapshot == .recording
    }

    public var isActive: Bool {
        switch statusSnapshot {
        case .recording, .chunking, .transcribing: return true
        default: return false
        }
    }

    /// Test initializer. Production uses `.shared`.
    /// Pass `recorder: nil` to lazily build a real `MeetingAudioCapture` per session.
    public init(
        store: MeetingTranscriptStore,
        recorder: MeetingAudioRecording?,
        chunker: @escaping Chunker,
        transcribe: @escaping Transcribe,
        apiKey: @escaping () -> String?,
        retainAudio: @escaping () -> Bool,
        backoffSchedule: [Double] = [1, 2, 4, 8, 16, 30]
    ) {
        self.store = store
        if let recorder = recorder {
            self.recorderFactory = { recorder }
        } else {
            self.recorderFactory = {
                if #available(macOS 13.0, *) { return MeetingAudioCapture() }
                fatalError("ScreenCaptureKit requires macOS 13+")
            }
        }
        self.chunker = chunker
        self.transcribe = transcribe
        self.apiKeyProvider = apiKey
        self.retainAudioProvider = retainAudio
        self.backoffSchedule = backoffSchedule
    }

    public enum SessionError: Error, CustomStringConvertible {
        case alreadyActive
        case notRecording
        case missingAPIKey

        public var description: String {
            switch self {
            case .alreadyActive: return "A meeting session is already active."
            case .notRecording: return "No active meeting session to stop."
            case .missingAPIKey: return "OpenAI API key missing."
            }
        }
    }

    public func start() async throws {
        lock.lock()
        guard session == nil else { lock.unlock(); throw SessionError.alreadyActive }
        let id = UUID()
        let now = Date()
        let title = "Meeting \(Self.titleFormatter.string(from: now))"
        let initial = TranscriptSession(
            id: id, title: title, startedAt: now, endedAt: nil,
            status: .recording, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: retainAudioProvider()
        )
        self.session = initial
        lock.unlock()

        try store.save(initial)

        let recorder = recorderFactory()
        self.recorder = recorder
        try await recorder.start(outputURL: store.audioFile(id: id))
    }

    public func stop() async throws {
        lock.lock()
        guard var current = session, current.status == .recording else {
            lock.unlock(); throw SessionError.notRecording
        }
        current.status = .chunking
        current.endedAt = Date()
        self.session = current
        lock.unlock()
        try store.save(current)

        guard let recorder = self.recorder else { throw SessionError.notRecording }
        let audioURL = try await recorder.stop()
        self.recorder = nil

        uploadTask = Task { [self, current] in
            await runChunkAndUpload(audioURL: audioURL, sessionID: current.id)
        }
    }

    public func cancel() {
        uploadTask?.cancel()
    }

    private func runChunkAndUpload(audioURL: URL, sessionID: UUID) async {
        let chunksDir = store.chunksDirectory(id: sessionID)
        let chunkURLs: [URL]
        do {
            chunkURLs = try await chunker(audioURL, chunksDir)
        } catch {
            updateSession { s in s.status = .failed }
            return
        }
        updateSession { s in
            s.chunksTotal = chunkURLs.count
            s.status = .transcribing
        }

        var completed = 0
        for (i, chunkURL) in chunkURLs.enumerated() {
            if Task.isCancelled { break }
            let offset = Double(i) * chunkDuration
            let segments: [TranscriptSegment]
            do {
                segments = try await transcribeWithInfiniteRetry(url: chunkURL, offset: offset)
            } catch is CancellationError {
                break
            } catch {
                // Non-transport error (auth, HTTP 4xx/5xx) — terminate session.
                updateSession { s in s.status = .failed }
                return
            }
            updateSession { s in
                s.segments.append(contentsOf: segments)
                completed += 1
                s.chunksCompleted = completed
            }
        }

        if Task.isCancelled {
            updateSession { s in s.status = .cancelled }
            return
        }

        updateSession { s in s.status = .completed }
        try? FileManager.default.removeItem(at: chunksDir)
        if !retainAudioProvider() {
            try? store.purgeAudio(for: sessionID)
        }
    }

    private func transcribeWithInfiniteRetry(
        url: URL, offset: Double
    ) async throws -> [TranscriptSegment] {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await transcribe(url, offset)
            } catch let TranscriptionError.transportError(_) {
                let delay = backoffSchedule[min(attempt, backoffSchedule.count - 1)]
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            } catch {
                throw error
            }
        }
    }

    private func updateSession(_ mutate: (inout TranscriptSession) -> Void) {
        lock.lock()
        guard var s = session else { lock.unlock(); return }
        mutate(&s)
        session = s
        lock.unlock()
        try? store.save(s)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
```

- [ ] **Step 4: Run session tests**

Run:
```bash
swift test --filter MeetingTranscriptionSessionTests 2>&1 | tail -20
```

Expected: 5 tests pass. (Cancel test may take ~3 seconds due to deliberate sleeps.)

- [ ] **Step 5: Run full suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 237 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/vox/STT/MeetingTranscriptionSession.swift Tests/voxTests/MeetingTranscriptionSessionTests.swift
git commit --no-gpg-sign -m "feat(meeting): MeetingTranscriptionSession state machine + tests (M2)"
```

---

## Task 8: MeetingPreflight live status + cold-recovery

**Files:**
- Modify: `Sources/vox/Meeting/MeetingPreflight.swift`
- Existing tests in `Tests/voxTests/MeetingPreflightTests.swift` must continue passing (they inject a stub provider, so the live default change does not break them).

- [ ] **Step 1: Replace the default backendStatusProvider**

Open `Sources/vox/Meeting/MeetingPreflight.swift`. Add `import CoreGraphics` at top if not present (currently only `import Foundation`).

Add the new `MeetingGateError` cases. Replace the existing `enum MeetingGateError` (lines 3-21) with:

```swift
import CoreGraphics
import Foundation

enum MeetingGateError: Error, Equatable, Sendable {
    case modeDisabled
    case consentRequired
    case backendUnavailable(reason: String)
    case missingAPIKey
    case permissionDenied(MeetingPermission)
    case captureFailed(String)
    case chunkingFailed(String)

    enum MeetingPermission: String, Equatable, Sendable {
        case screenRecording
    }

    var userMessage: String {
        switch self {
        case .modeDisabled:
            return "Meeting Mode is off. Enable it in Settings → Meeting Transcription (Beta)."
        case .consentRequired:
            return "Meeting capture requires a one-time acknowledgment. Open Settings → Meeting Transcription (Beta)."
        case .backendUnavailable(let reason):
            return "Meeting capture is unavailable: \(reason)"
        case .missingAPIKey:
            return "OpenAI API key is required. Add one in Settings."
        case .permissionDenied(let perm):
            switch perm {
            case .screenRecording:
                return "Screen Recording permission required. Open System Settings → Privacy & Security → Screen Recording and enable Vox."
            }
        case .captureFailed(let msg):
            return "Meeting capture failed: \(msg)"
        case .chunkingFailed(let msg):
            return "Could not split audio for transcription: \(msg)"
        }
    }
}
```

Replace the `backendStatusProvider` default (lines 38-40) with the live check:

```swift
    /// Backend availability hook injected for tests; production resolves to the live status check.
    static var backendStatusProvider: @Sendable (MeetingCaptureBackend) -> MeetingBackendStatus = { backend in
        liveStatus(for: backend)
    }

    static func liveStatus(for backend: MeetingCaptureBackend) -> MeetingBackendStatus {
        switch backend {
        case .systemAudio:
            if CGPreflightScreenCaptureAccess() {
                return MeetingBackendStatus(
                    available: true,
                    detail: "ScreenCaptureKit ready."
                )
            } else {
                return MeetingBackendStatus(
                    available: false,
                    detail: "Screen Recording permission not granted."
                )
            }
        }
    }
```

- [ ] **Step 2: Run existing preflight tests (must still pass)**

Run:
```bash
swift test --filter MeetingPreflightTests 2>&1 | tail -10
```

Expected: 6 tests pass — existing tests inject `backendStatusProvider`, unaffected by the new default.

- [ ] **Step 3: Run full suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 237 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/vox/Meeting/MeetingPreflight.swift
git commit --no-gpg-sign -m "feat(meeting): live preflight via CGPreflightScreenCaptureAccess + new error cases (M2)"
```

---

## Task 9: Mutex — block dictation Fn-hold while meeting recording

**Files:**
- Modify: `Sources/vox/Audio/KeyboardController.swift` (mutex check)
- Create: `Tests/voxTests/MeetingMutexTests.swift`

The mutex reads `MeetingTranscriptionSession.shared.isRecording`. We make this a closure-injectable check so tests can swap in a stub without touching the singleton.

- [ ] **Step 1: Identify the Fn-down handler**

Read `Sources/vox/Audio/KeyboardController.swift` to find the function that fires when the record hotkey goes down (likely `handleFnDown` or similar — search for the hotkey-down code path that calls into AudioRecorder.start).

Run:
```bash
grep -n "AudioRecorder\|fnDown\|keyDown\|handleHot\|recordHotkey" Sources/vox/Audio/KeyboardController.swift | head -20
```

Note the function name and line number for the next step.

- [ ] **Step 2: Add an injectable mutex hook**

At the top of `KeyboardController.swift` (after imports), add:

```swift
/// Mutex hook: returns true when something else (currently only meeting recording)
/// has taken over the audio path and dictation hotkey must be ignored.
/// Production resolves to `MeetingTranscriptionSession.shared.isRecording`.
/// Tests swap this for a stub.
public enum DictationMutex {
    public static var isBlocked: () -> Bool = {
        MeetingTranscriptionSession.shared.isRecording
    }
}
```

In the Fn-down handler (the function identified in Step 1), add an early-return at the very top:

```swift
        if DictationMutex.isBlocked() {
            // Meeting recording is active; suppress dictation hotkey.
            return
        }
```

- [ ] **Step 3: Write the failing test**

Create `Tests/voxTests/MeetingMutexTests.swift`:

```swift
import XCTest
@testable import vox

final class MeetingMutexTests: XCTestCase {
    override func tearDown() {
        DictationMutex.isBlocked = { false }
        super.tearDown()
    }

    func testMutexBlocksWhenMeetingRecording() {
        DictationMutex.isBlocked = { true }
        XCTAssertTrue(DictationMutex.isBlocked())
    }

    func testMutexDoesNotBlockWhenIdle() {
        DictationMutex.isBlocked = { false }
        XCTAssertFalse(DictationMutex.isBlocked())
    }
}
```

This is a thin coverage of the wiring; the integration check (Fn actually ignored) is exercised in Task 11 manual smoke. Adding deeper tests would require KeyboardController instantiation which depends on real CGEvent taps and is brittle.

- [ ] **Step 4: Run mutex tests**

Run:
```bash
swift test --filter MeetingMutexTests 2>&1 | tail -10
```

Expected: 2 tests pass.

- [ ] **Step 5: Run full suite (regression check)**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 239 tests, 0 failures. `DictationRegressionTests` must still pass — confirms the early-return doesn't fire for normal dictation.

- [ ] **Step 6: Commit**

```bash
git add Sources/vox/Audio/KeyboardController.swift Tests/voxTests/MeetingMutexTests.swift
git commit --no-gpg-sign -m "feat(meeting): block dictation Fn-hold while meeting recording (M2)"
```

---

## Task 10: MenuBarController — wire Start/Stop + Show Transcripts

**Files:**
- Modify: `Sources/vox/App/MenuBarController.swift`

Replaces the M1 stubs at lines 276-302. Adds a new "Show Meeting Transcripts…" item alongside Start/Stop.

- [ ] **Step 1: Add the menu item**

Open `Sources/vox/App/MenuBarController.swift`. In `configureMenu()` around line 130-150 where the M1 Start/Stop items live, add a third menu item right below Stop:

```swift
            let showTranscripts = NSMenuItem(
                title: "Show Meeting Transcripts…",
                action: #selector(showMeetingTranscripts),
                keyEquivalent: ""
            )
            showTranscripts.target = self
            menu.addItem(showTranscripts)
```

- [ ] **Step 2: Replace the Start handler to use the live session**

Replace `startMeetingTranscript()` (currently lines 276-289) with:

```swift
    @objc private func startMeetingTranscript() {
        let result = MeetingPreflight.gate(hasAPIKey: keychain.read()?.isEmpty == false)
        if case .failure(let err) = result {
            dlog("meeting gate denied: \(err)")
            presentMeetingError(err.userMessage)
            return
        }
        // Block start if dictation is mid-flight (mirror of the Fn-hold mutex).
        if AudioRecorder.shared.isRecording {
            presentMeetingError("Finish current dictation before starting a meeting.")
            return
        }
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.start()
                self.refreshIcon()  // optional: surface a "meeting recording" icon variant
            } catch {
                self.presentMeetingError("Could not start meeting: \(error)")
            }
        }
    }
```

NOTE: This assumes `AudioRecorder` has a `shared` instance and a public `isRecording` property. If it does not, either:
- Add `public static let shared = AudioRecorder()` and use the existing instance there, OR
- Promote the existing `private var isRecording = false` to `public private(set) var isRecording = false`, AND wire whatever singleton accessor is used today.

Verify by reading `Sources/vox/Audio/AudioRecorder.swift` and the call sites in `MenuBarController.swift` first; pick the minimal change.

- [ ] **Step 3: Replace the Stop handler**

Replace `stopMeetingTranscript()` (currently lines 291-293) with:

```swift
    @objc private func stopMeetingTranscript() {
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.stop()
                MeetingTranscriptsWindow.shared.show()
            } catch {
                self.presentMeetingError("Could not stop meeting: \(error)")
            }
        }
    }
```

- [ ] **Step 4: Add the Show Transcripts handler**

Anywhere in `MenuBarController` (alongside the other meeting handlers):

```swift
    @objc private func showMeetingTranscripts() {
        MeetingTranscriptsWindow.shared.show()
    }
```

- [ ] **Step 5: Add cold-recovery on app launch**

In `AppDelegate.swift` (or wherever the app boots up — check `Sources/vox/App/AppDelegate.swift`), after the menu bar is set up, add a one-line cold-recovery sweep:

```swift
        MeetingTranscriptStore().recoverInFlightSessions()
```

This resets any session left in `.recording`/`.chunking`/`.transcribing` state by a prior process to `.failed`, so the transcripts window does not show stuck spinners.

- [ ] **Step 6: Build (will fail until Task 11 lands MeetingTranscriptsWindow)**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: build error referencing `MeetingTranscriptsWindow` undefined. That is intentional — Task 11 lands the window. Do NOT commit yet; finish Task 11 first and commit them together.

---

## Task 11: MeetingTranscriptsWindow

**Files:**
- Create: `Sources/vox/App/MeetingTranscriptsWindow.swift`

SwiftUI hosted in an NSWindow. Singleton accessor `shared.show()` for the menu bar.

- [ ] **Step 1: Write the window + view code**

Create `Sources/vox/App/MeetingTranscriptsWindow.swift`:

```swift
import AppKit
import Combine
import SwiftUI

@MainActor
public final class MeetingTranscriptsWindow {
    public static let shared = MeetingTranscriptsWindow()

    private var window: NSWindow?

    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MeetingTranscriptsView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Meeting Transcripts"
        win.setContentSize(NSSize(width: 720, height: 480))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class MeetingTranscriptsModel: ObservableObject {
    @Published var sessions: [TranscriptSession] = []
    @Published var selection: UUID?
    private let store = MeetingTranscriptStore()
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .meetingTranscriptStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() }
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    func reload() {
        sessions = store.list()
        if selection == nil { selection = sessions.first?.id }
    }

    func selected() -> TranscriptSession? {
        guard let id = selection else { return nil }
        return sessions.first { $0.id == id }
    }

    func delete(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = "Delete this transcript?"
        alert.informativeText = "This permanently removes the transcript and any kept audio."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            try? store.delete(id: id)
            reload()
        }
    }

    func cancelActive(_ id: UUID) {
        if MeetingTranscriptionSession.shared.activeSessionID == id {
            MeetingTranscriptionSession.shared.cancel()
        }
    }

    func export(_ session: TranscriptSession, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.title).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = format.render(session: session)
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    enum ExportFormat {
        case plain, timestamped
        func render(session: TranscriptSession) -> String {
            switch self {
            case .plain:
                var out = ""
                var lastEnd: Double = -1
                for seg in session.segments {
                    if lastEnd >= 0, seg.startTime - lastEnd > 2.0 { out += "\n\n" }
                    else if !out.isEmpty { out += " " }
                    out += seg.text
                    lastEnd = seg.endTime
                }
                return out
            case .timestamped:
                return session.segments.map { seg in
                    "[\(formatTime(seg.startTime))] \(seg.text)"
                }.joined(separator: "\n")
            }
        }
        private func formatTime(_ t: Double) -> String {
            let total = Int(t)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%02d:%02d", m, s)
        }
    }
}

private struct MeetingTranscriptsView: View {
    @StateObject private var model = MeetingTranscriptsModel()

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 240, idealWidth: 260)
            detail
        }
        .frame(minWidth: 600, minHeight: 360)
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            ForEach(model.sessions, id: \.id) { session in
                SidebarRow(session: session, onCancel: { model.cancelActive(session.id) })
                    .tag(session.id)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let s = model.selected() {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.title).font(.headline)
                    Spacer()
                    Menu("Export") {
                        Button("Plain Text") { model.export(s, format: .plain) }
                        Button("Timestamped Text") { model.export(s, format: .timestamped) }
                    }
                    Button("Delete") { model.delete(s.id) }
                }.padding()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(s.segments.enumerated()), id: \.offset) { _, seg in
                            HStack(alignment: .top) {
                                Text(formatTime(seg.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(seg.text).textSelection(.enabled)
                            }.padding(.horizontal)
                        }
                    }.padding(.vertical, 6)
                }
            }
        } else {
            Text("No transcripts yet.").foregroundColor(.secondary)
        }
    }

    private func formatTime(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct SidebarRow: View {
    let session: TranscriptSession
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.body)
            HStack(spacing: 6) {
                Text(durationText).foregroundColor(.secondary).font(.caption)
                statusBadge
                if session.status == .transcribing {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.borderless)
                }
            }
        }.padding(.vertical, 2)
    }

    private var durationText: String {
        guard let end = session.endedAt else { return "Recording…" }
        let secs = Int(end.timeIntervalSince(session.startedAt))
        let m = secs / 60, s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .recording:
            Text("Recording").foregroundColor(.red).font(.caption)
        case .chunking:
            Text("Chunking…").foregroundColor(.orange).font(.caption)
        case .transcribing:
            Text("Transcribing \(session.chunksCompleted)/\(session.chunksTotal)")
                .foregroundColor(.orange).font(.caption)
        case .completed:
            Text("Done").foregroundColor(.green).font(.caption)
        case .cancelled:
            Text("Cancelled").foregroundColor(.secondary).font(.caption)
        case .failed:
            Text("Failed").foregroundColor(.red).font(.caption)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: clean build now (`MeetingTranscriptsWindow` exists; `MenuBarController` from Task 10 references resolve).

- [ ] **Step 3: Run full suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: 239 tests, 0 failures.

- [ ] **Step 4: Commit Tasks 10 + 11 together**

```bash
git add Sources/vox/App/MenuBarController.swift Sources/vox/App/MeetingTranscriptsWindow.swift Sources/vox/App/AppDelegate.swift Sources/vox/Audio/AudioRecorder.swift
git commit --no-gpg-sign -m "feat(meeting): wire MenuBar Start/Stop + transcripts window (M2)"
```

(If `AudioRecorder.swift` was modified to expose `isRecording`/`shared`, include it; otherwise drop it from the add list.)

---

## Task 12: Integration smoke + dictation regression + manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run full test suite**

Run:
```bash
swift test 2>&1 | tail -3
```

Expected: ~239 tests, 0 failures.

- [ ] **Step 2: Run dictation regression**

Run:
```bash
./scripts/run-dictation-regression.sh
```

Expected: same baseline as Task 0 Step 2 — `failure_rate=0.0 quality_score=1.0 latency_ms=4` (or the captured baseline). If quality drops or latency rises, halt and investigate before merging.

- [ ] **Step 3: Build the app bundle**

Run:
```bash
./scripts/build-app.sh
```

Expected: clean build of `dist/Vox.app` (or wherever build-app.sh writes output).

- [ ] **Step 4: Manual smoke — meeting happy path**

Tell the user (via NSAlert or console log) what to do:

1. Quit running Vox: `pkill -9 -f 'Vox.app/Contents/MacOS/vox'`
2. Launch the freshly built app.
3. Open Settings → Meeting Transcription (Beta) → enable Meeting Mode + acknowledge consent.
4. Menu bar → Start Meeting Transcript. Approve Screen Recording prompt if it appears.
5. Play a 30-second YouTube clip with clear speech.
6. Menu bar → Stop Meeting Transcript.
7. Transcripts window opens. Sidebar shows new session with `Transcribing 1/1`. Within ~30s status flips to `Done`.
8. Detail pane shows segments with `mm:ss` timestamps.
9. Export → Plain Text → save → open file → verify content reads naturally.
10. Export → Timestamped Text → verify each line has `[mm:ss]` prefix.

If any step fails, capture the failure and triage before declaring M2 done.

- [ ] **Step 5: Manual smoke — mutex**

1. With Vox running, hold Fn → speak → release. Confirm dictation works.
2. Start a meeting transcript.
3. Hold Fn → speak → release. Confirm dictation does NOT activate (no orange icon, no transcription posted).
4. Stop meeting. Hold Fn → speak → release. Confirm dictation works again.

- [ ] **Step 6: Manual smoke — cancel mid-transcribe**

1. Record a 12-min meeting (3 chunks).
2. After Stop, while sidebar shows `Transcribing 1/3`, click the cancel `(x)`.
3. Status flips to `Cancelled`. Detail pane shows partial segments from chunk 0.

- [ ] **Step 7: Manual smoke — audio retain toggle**

1. Settings → enable "Keep audio recording after transcription".
2. Record + stop a short meeting. After completion, in Finder open `~/Library/Application Support/Vox/MeetingTranscripts/<uuid>/` — confirm `audio.m4a` exists.
3. Settings → disable the toggle. Record + stop a new meeting. Confirm `audio.m4a` does NOT exist for the new session, but the old one is still there.

- [ ] **Step 8: Update HANDOFF.md**

Open `HANDOFF.md`. Add a new top section:

```markdown
## Session 2026-04-29 (or current date) — Meeting Transcription M2 shipped

**Status:** Committed across multiple commits on `main` (see `git log`). `swift test` passes (~239 tests). Dictation regression baseline unchanged. Manual smoke verified for happy path, mutex, cancel, and audio-retain toggle.

**What landed:**
- `MeetingTranscriptStore` + `TranscriptSession` model
- `MeetingChunker` (5-min AAC slices)
- `MeetingAudioCapture` (SCStream → AAC m4a)
- `MeetingTranscriptionSession` state machine (record → chunk → upload-with-infinite-retry → persist)
- `OpenAITranscriber.transcribeMeetingChunk` (verbose_json + offset stitching)
- `MeetingTranscriptsWindow` (NSWindow + SwiftUI sidebar + detail + export)
- Mutex: dictation Fn-hold blocked while meeting recording
- Live `MeetingPreflight` via `CGPreflightScreenCaptureAccess`
- Cold-recovery sweep on launch
- `meetingRetainAudio` setting (default off)

**Next:** M3 hardening — telemetry, resource isolation, help docs (see `docs/superpowers/plans/2026-04-29-meeting-transcription-additive.md`).
```

- [ ] **Step 9: Commit handoff + final check**

```bash
git add HANDOFF.md
git commit --no-gpg-sign -m "docs(meeting): HANDOFF — M2 shipped"
git push origin main
```

Then verify:

```bash
git status
git log --oneline -10
```

Expected: clean tree on `main` in sync with `origin/main`. Recent log shows M2 commits.

---

## Self-review notes (for the implementer)

If you hit a step that's wrong:
- **Build error referencing missing M1 type:** the M1 commit `12d508e` is the assumed baseline. Verify with `git show 12d508e --stat`.
- **`AudioRecorder.shared` doesn't exist:** Pick whichever pattern the existing dictation call site uses. The minimal fix is to add a public `isRecording` accessor and read it through the existing instance the menu bar already holds (search `MenuBarController` for `AudioRecorder` references).
- **Test compile fails on `try await asset.load(.duration).seconds`:** macOS 13+ async asset API. If swift-package targets older OS, use `let dur = CMTimeGetSeconds(asset.duration)` synchronously instead — but Vox's `Package.swift` already pins macOS 13+ (per appcast `<sparkle:minimumSystemVersion>13.0`).
- **`MeetingTranscriptionSessionTests` cancel test flakes:** the deliberate 2s sleep is there to ensure cancel lands mid-call. If it still flakes, raise `cancelAfter` semantics — but the test is intentionally racy; flakes there indicate the upload loop is not honoring `Task.checkCancellation()`.
- **Dictation regression drops:** halt. The mutex check or anything in `KeyboardController` is the prime suspect. Bisect commits.

Plan complete.
