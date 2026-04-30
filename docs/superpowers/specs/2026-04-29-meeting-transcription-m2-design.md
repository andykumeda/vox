# Meeting Transcription M2 — Design Spec (2026-04-29)

## Objective

Implement the meeting-transcription pipeline on top of the M1 scaffolding (commit `12d508e`): record system audio, transcribe end-of-meeting via chunked Whisper uploads, persist timestamped transcripts, and present them in a dedicated window. Existing dictation STT must remain unchanged.

## Locked product decisions

| # | Decision | Source |
|---|----------|--------|
| 1 | Capture source: system/call audio only | M1 plan (locked) |
| 2 | Output UX: in-app transcript list + export | M1 plan (locked) |
| 3 | No diarization in v1 | M1 plan (locked) |
| 4 | One-time consent acknowledgment | M1 plan (locked) |
| 5 | Storage: Application Support (app-managed) | M1 plan (locked) |
| 6 | No regression on existing dictation STT | M1 plan (locked) |
| 7 | Transcription cadence: end-of-meeting only (record full audio, transcribe after Stop) | This spec |
| 8 | Max meeting duration: 2 hours | This spec |
| 9 | Chunk boundaries: fixed 5-minute time slices | This spec |
| 10 | Transcript UI: dedicated NSWindow with sidebar list + detail pane | This spec |
| 11 | Per-chunk failure policy: infinite retry with backoff, user-cancellable | This spec |
| 12 | Raw audio post-success: settings toggle, default delete | This spec |
| 13 | Progress UI: non-blocking, chunk count `N/M` in sidebar row | This spec |
| 14 | Mutex: dictation Fn-hold disabled while meeting recording | This spec |
| 15 | Timestamp granularity: Whisper-native segments (~5–15s) | This spec |

## Architecture overview

Five new units. Existing dictation code paths (`AudioRecorder`, `OpenAITranscriber.transcribe(...)`, `KeyboardController` Fn-hold logic, `MenuBarController` dictation actions) are not modified except for the mutex check in `KeyboardController` and a new menu item in `MenuBarController`.

```
┌──────────────────────────┐    ┌──────────────────────────────────┐
│ MeetingAudioCapture      │───▶│ MeetingTranscriptionSession      │
│ (SCStream → AAC m4a)     │    │ state machine: record → chunking │
└──────────────────────────┘    │ → transcribing → completed       │
                                │ infinite-retry chunk uploader     │
                                └────────┬──────────────────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
┌──────────────────────────┐ ┌──────────────────────────┐ ┌──────────────────────────┐
│ OpenAITranscriber        │ │ MeetingTranscriptStore   │ │ MeetingTranscriptsWindow │
│ + transcribeMeetingChunk │ │ JSON in App Support      │ │ NSWindow + SwiftUI       │
└──────────────────────────┘ └──────────────────────────┘ └──────────────────────────┘
```

## Components

### MeetingAudioCapture

`Sources/vox/Meeting/MeetingAudioCapture.swift`

- Uses ScreenCaptureKit (`SCStream` + `SCContentFilter` against `SCDisplay[0]`) with `excludesCurrentProcessAudio = true` to avoid feedback from Vox's own output.
- `SCStreamConfiguration.capturesAudio = true`, `sampleRate = 16000`, `channelCount = 1`.
- Audio output handler receives `CMSampleBuffer` (PCM); `AVAssetWriter` + `AVAssetWriterInput` (kAudioFormatMPEG4AAC, 64 kbps mono, 16 kHz) writes AAC m4a.
- File path: `<AppSupport>/Vox/MeetingTranscripts/<uuid>/audio.m4a`.
- Public API: `start() async throws`, `stop() async -> URL`.
- Preflight: throws `MeetingGateError.permissionDenied(.screenRecording)` if `CGPreflightScreenCaptureAccess() == false`.
- Sizing: 64 kbps mono = ~28 MB/hr; 2-hr max = ~56 MB; 5-min chunk ≈ 2.4 MB (well under Whisper's 25 MB limit).

### MeetingTranscriptionSession

`Sources/vox/STT/MeetingTranscriptionSession.swift`

State machine:

```
idle ── start() ──▶ recording ── stop() ──▶ stopping ──▶ chunking
                                                              │
                                                              ▼
                                                       transcribing
                                                              │
                                          ┌───────────────────┼───────────────────┐
                                          ▼                                       ▼
                                      completed                              cancelled
                                                                  (only via user cancel)
```

- Singleton `MeetingTranscriptionSession.shared`. Exposes `var isRecording: Bool`, `var isActive: Bool` (recording or transcribing).
- `start()` instantiates `MeetingAudioCapture`, sets `status = .recording`, persists initial `TranscriptSession` row to store.
- `stop()` finalizes capture file, transitions to `.chunking`.
- **Chunking**: opens finalized .m4a via `AVAsset`, slices into 5-min segments via `AVAssetExportSession` with `timeRange = CMTimeRange(start: i*300s, duration: 300s)`. Output AAC m4a per chunk to `<sessionDir>/chunks/000.m4a`, `001.m4a`, …
- **Upload queue**: serial `Task` loop (parallelism = 1, preserves ordering and respects API rate limits). Per chunk, calls `OpenAITranscriber.transcribeMeetingChunk(url, offsetSeconds: i*300)`.
- **Per-chunk retry policy**: on retry-eligible `URLError` codes (`.timedOut`, `.networkConnectionLost`, `.dnsLookupFailed`, `.notConnectedToInternet`, `.cannotConnectToHost`), backoff 1s → 2s → 4s → 8s, capped at 30s, retried **forever** until success or user cancel. Auth/HTTP errors throw immediately and terminate the session as `.failed`.
- After each chunk completes, appends returned segments to `TranscriptSession.segments` (offsets already absolute), persists via store, publishes update via `AsyncStream<MeetingProgress>` (fields: `chunksCompleted`, `chunksTotal`).
- **Cancel**: user-initiated → `Task.cancel()` propagates, status `.cancelled`, partial segments persisted, `chunks/` dir kept for debug, audio kept regardless of `meetingRetainAudio` setting.
- **Cleanup on success**: `chunks/` dir deleted; `audio.m4a` deleted unless `meetingRetainAudio == true`.

### OpenAITranscriber additions

`Sources/vox/STT/OpenAITranscriber.swift` — additive only; existing `transcribe(...)` and `sendWithRetry(...)` (added in `7bc8cad`) are not modified.

```swift
struct WhisperSegment: Decodable {
    let start: Double
    let end: Double
    let text: String
}

static func transcribeMeetingChunk(
    fileURL: URL,
    offsetSeconds: Double,
    apiKey: String
) async throws -> [TranscriptSegment]
```

- Multipart POST to `/v1/audio/transcriptions` with `model=whisper-1`, `response_format=verbose_json`, `timestamp_granularities[]=segment`.
- Decodes `{ segments: [WhisperSegment] }`.
- Maps to `TranscriptSegment(startTime: seg.start + offsetSeconds, endTime: seg.end + offsetSeconds, text: seg.text.trimmingCharacters(in: .whitespaces))`.
- `request.timeoutInterval = 120.0` — chunk uploads (~2.4 MB) need more headroom than dictation's 30s.
- Reuses existing `sendWithRetry` for transient transport errors. Caller (`MeetingTranscriptionSession`) implements the outer infinite-retry loop.

### MeetingTranscriptStore

`Sources/vox/Util/MeetingTranscriptStore.swift`

```swift
struct TranscriptSegment: Codable {
    let startTime: Double
    let endTime: Double
    let text: String
}

struct TranscriptSession: Codable {
    let id: UUID
    var title: String           // default: "Meeting yyyy-MM-dd HH:mm"
    let startedAt: Date
    var endedAt: Date?
    var status: Status
    var chunksTotal: Int
    var chunksCompleted: Int
    var segments: [TranscriptSegment]
    var audioRetained: Bool

    enum Status: String, Codable {
        case recording, chunking, transcribing, completed, cancelled, failed
    }
}
```

Layout:

```
~/Library/Application Support/Vox/MeetingTranscripts/
  <uuid>/
    transcript.json    # canonical, atomic write
    audio.m4a          # only if audioRetained == true after success
    chunks/            # always deleted post-success
```

API:

- `list() -> [TranscriptSession]` — reads all `*/transcript.json`, sorted by `startedAt` desc.
- `load(id: UUID) -> TranscriptSession?`
- `save(_ session: TranscriptSession)` — atomic via `Data.write(to:options: .atomic)`.
- `delete(id: UUID)` — removes whole `<uuid>/` dir.
- `purgeAudio(for id: UUID)` — removes `audio.m4a`, sets `audioRetained = false`, re-saves transcript.

Posts `NotificationCenter` event `meetingTranscriptStoreDidChange` on each save → window refreshes.

### Settings additions

`Sources/vox/Util/AppSettings.swift`:

```swift
@Storage(key: "meetingRetainAudio", defaultValue: false)
var meetingRetainAudio: Bool
```

Surfaced in `SettingsWindow.swift` "Meeting Transcription (Beta)" section: "Keep audio recording after transcription (default off)".

### MeetingTranscriptsWindow

`Sources/vox/App/MeetingTranscriptsWindow.swift` — lazy `NSWindow` singleton, SwiftUI host (`NSHostingView`).

Layout:

```
┌─ Meeting Transcripts ──────────────────────────────────┐
│ Sidebar (NSSplitView left, ~260pt)  │ Detail (right)   │
│ ─────────────────────────────────── │ ──────────────── │
│  • 2026-04-29  17:42                │ Title (editable) │
│    1h 12m · Transcribing 4/24  (✕)  │ ──────────────── │
│  • 2026-04-28  10:00  ✓             │ 00:00:05  Hello… │
│    32m                              │ 00:00:18  So…    │
│  • 2026-04-27  ✗ Cancelled          │ 00:00:34  …      │
│                                     │                  │
│                                     │ [Export ▾] [Del] │
└─────────────────────────────────────────────────────────┘
```

- Sidebar row: title, date, duration, status badge. Active row shows live `Transcribing N/M` with cancel button.
- Detail: scrollable `LazyVStack` of segments. Each row: `mm:ss` timestamp + text. Click timestamp → copies to pasteboard.
- Toolbar Export menu:
  - **Plain Text** — segments joined by single space, paragraph break on >2s gap.
  - **Timestamped Text** — one line per segment: `[mm:ss] text`.
- Save panel default filename: `<session.title>.txt`.
- Delete confirms via NSAlert (`messageText = "Delete this transcript?"`, destructive style).

Menu bar additions in `MenuBarController` (gated by `meetingModeEnabled`):

- `Show Meeting Transcripts…` → opens window.
- Existing `Start/Stop Meeting Transcript` items remain. **Stop** now triggers `MeetingTranscriptionSession.shared.stop()` (replaces M1's stub alert).

### Mutex

- `MeetingTranscriptionSession.shared.isRecording` consulted in `KeyboardController.handleFnDown()`. If true, early-return; show menu/OSD tooltip "Stop meeting recording first." on first attempt per session.
- Reverse direction (block meeting Start while dictation is mid-flight): add an explicit dictation-active check inside the M1 `Start Meeting Transcript` action handler in `MenuBarController` — reads `AudioRecorder.shared.isRecording` (or equivalent existing dictation state). If true, surface NSAlert "Finish current dictation first." and abort. This is a new gate added in M2; M1's `MeetingPreflight.gate(...)` does not cover it (the preflight is environment-level, not runtime-state).

### Preflight

`Sources/vox/Meeting/MeetingPreflight.swift`:

- Replace `backendStatusProvider` default with live implementation:
  - Check `CGPreflightScreenCaptureAccess() == true`.
  - Check API key present in keychain (via existing `KeychainStore`).
  - Returns `.available` iff both pass; else `.unavailable(reason: String)`.
- New `MeetingGateError` cases:
  - `.permissionDenied(.screenRecording)`
  - `.captureFailed(underlying: Error)`
  - `.chunkingFailed(underlying: Error)`

Existing M1 tests in `MeetingPreflightTests.swift` remain green (injection point unchanged).

### Error surface

- Capture/chunking failures → NSAlert with `MeetingGateError.userMessage`. Session row marked `.failed`.
- Per-chunk transient transport failures → silent retry per backoff schedule. Sidebar row caption switches to "Retrying chunk N…" after 3 consecutive failures, returns to normal on success.
- User cancel mid-upload → status `.cancelled`, partial transcript on disk, audio retained regardless of setting.

## Testing

New test files in `Tests/voxTests/`. ~20 new tests; suite grows from 221 → ~241. `DictationRegressionTests` baseline (failure_rate=0.0, quality=1.0, latency≤4ms) must remain unchanged.

| File | ~Tests | Coverage |
|------|--------|----------|
| `MeetingTranscriptStoreTests` | 6 | Codable round-trip, list ordering, delete removes dir, `purgeAudio` keeps json, atomic write survives crash sim |
| `MeetingChunkerTests` | 4 | Fixture m4a (12-min generated sine) → 3 chunks, durations 300/300/120s, valid AAC |
| `TimestampStitchingTests` | 3 | Mock `WhisperSegment` arrays per chunk, verify absolute = `chunk_offset + whisper_offset`, edges (offset=0, last partial) |
| `MeetingTranscriptionSessionTests` | 5 | Happy path, transient retry, infinite retry holds, user cancel mid-upload, audio retain off |
| `MeetingMutexTests` | 2 | Fn-hold ignored while session recording, allowed after stop |

Whisper API not exercised live: `OpenAITranscriber.transcribeMeetingChunk` covered by an injected `URLSession` stub returning canned JSON. The chunk method takes `urlSession: URLSession = .shared` as a parameter so tests can inject `URLSessionConfiguration.ephemeral` with `URLProtocol` stub.

## Non-goals (v1)

- Diarization / speaker labels.
- Live transcription during recording (locked: end-of-meeting only).
- Concurrent meeting + dictation.
- Background continuation when app quits mid-recording (Stop must be explicit; abrupt quit results in incomplete `audio.m4a` and `.failed` session on next launch).
- Cloud sync of transcripts.

## Out-of-scope deferred to M3

- Telemetry + redaction.
- Resource isolation between meeting and dictation request paths (currently mutex prevents concurrent execution).
- Help docs for consent + meeting troubleshooting.

## Risk register

| Risk | Mitigation |
|------|------------|
| ScreenCaptureKit Screen Recording TCC prompt unfamiliar to users | First-launch flow surfaces clear NSAlert linking to System Settings; preflight catches missing permission cleanly |
| Whisper rate limit hit on rapid back-to-back 2-hr meetings | Serial upload (parallelism=1) + retry/backoff respects 429s. Per-meeting cost ~$0.36 — acceptable |
| Disk fill from retained audio | `meetingRetainAudio` defaults to false; user must opt in |
| ScreenCaptureKit captures audio from Vox itself (echo) | `excludesCurrentProcessAudio = true` |
| Crash mid-upload corrupts transcript.json | Atomic writes; on relaunch, sessions in `.recording`, `.chunking`, or `.transcribing` state must be reset to `.failed` (cold-recovery sweep on `MeetingTranscriptStore.list()` first call per launch) |
| User force-quits during recording | `audio.m4a` truncated; session marked `.failed` on next launch; user can choose to delete or retry chunking from partial file |

## File inventory

New:
- `Sources/vox/Meeting/MeetingAudioCapture.swift`
- `Sources/vox/STT/MeetingTranscriptionSession.swift`
- `Sources/vox/Util/MeetingTranscriptStore.swift`
- `Sources/vox/App/MeetingTranscriptsWindow.swift`
- `Tests/voxTests/MeetingTranscriptStoreTests.swift`
- `Tests/voxTests/MeetingChunkerTests.swift`
- `Tests/voxTests/TimestampStitchingTests.swift`
- `Tests/voxTests/MeetingTranscriptionSessionTests.swift`
- `Tests/voxTests/MeetingMutexTests.swift`

Modified (additive only, no behavior change to dictation):
- `Sources/vox/Util/AppSettings.swift` — `meetingRetainAudio` key
- `Sources/vox/STT/OpenAITranscriber.swift` — `transcribeMeetingChunk(...)` static method
- `Sources/vox/Meeting/MeetingPreflight.swift` — live `backendStatusProvider`, new error cases
- `Sources/vox/App/MenuBarController.swift` — `Show Meeting Transcripts…` item; Stop wired to session
- `Sources/vox/App/SettingsWindow.swift` — "Keep audio after transcription" toggle
- `Sources/vox/Audio/KeyboardController.swift` — Fn-hold mutex check

## Acceptance criteria

1. User enables Meeting Mode + acknowledges consent → preflight passes (Screen Recording permission granted, API key present).
2. User runs `Start Meeting Transcript` → records system audio for any duration up to 2 hr.
3. User runs `Stop Meeting Transcript` → sees session row appear in Transcripts window with `Transcribing N/M` progress, non-blocking.
4. On completion, transcript visible in detail pane with `mm:ss` timestamps; both export formats produce correct output.
5. User can cancel mid-transcription; partial transcript preserved.
6. Setting `Keep audio recording after transcription = false` (default) → `audio.m4a` deleted on success.
7. Dictation Fn-hold ignored while meeting recording; works normally otherwise.
8. `DictationRegressionTests` passes with same baseline.
9. `swift build` and `swift test` clean (suite ≈ 241).
