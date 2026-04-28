# Smart Cleanup (Prose Mode) — Design

**Date:** 2026-04-28
**Status:** Design approved, ready for implementation plan
**Owner:** Andy

## Problem

In prose mode, dictated speech often contains:

- **Self-corrections** mid-utterance ("Send to Marcus, actually no, send to Lena.").
- **Filler words** ("um", "uh") and false starts.
- **Run-on sentences** that the speaker would punctuate naturally on a re-read.

Today Vox transcribes verbatim and pastes whatever the STT model returns. The
2026-04-28 STT bench confirmed this is shared across the entire Whisper
family — switching providers won't fix it. Andy needs an interpretation layer
between transcription and paste that produces the *intended* prose, not the
*spoken* prose.

He also wants a small set of *explicit* edit commands ("scratch that") that
work deterministically for cases where natural-language cleanup is
unreliable or unwanted.

## Goal

Add an opt-in cleanup pass that runs after `PostProcessor` and before
`TextInjector`, so prose dictations can be polished by a small LLM and a few
hard trigger phrases. Default off; user toggles in Settings.

**Non-goals:**

- Provider switch for the STT call itself (that's a separate spec; see
  `docs/superpowers/specs/2026-04-28-stt-bench-design.md` for context).
- Streaming / partial-result transcription.
- Native Apple Speech framework integration.
- Voice commands beyond the 3 specified hard triggers.
- Full grammar correction or rewriting (e.g. style, tone, formality).
- Multi-language cleanup (English only, matching current scope).
- Per-app behavior (cleanup runs the same regardless of focused app).

## Approach

A new component `CleanupProcessor` runs after `PostProcessor` in the
existing pipeline:

```
Audio → AudioRecorder → OpenAITranscriber → PostProcessor → CleanupProcessor → TextInjector
```

`CleanupProcessor` does two things:

1. **Three deterministic trigger phrases** — `scratch that` / `delete that`,
   `new paragraph`, `new line` — applied via regex with sentence-boundary
   anchoring to keep false positives low. These run in *both* prose and
   command mode (when the feature is enabled), since explicit edit commands
   are useful in both contexts.
2. **A LLM cleanup pass** via OpenAI `gpt-4o-mini` to remove false starts,
   filler words, and self-corrections. Runs *only* in prose mode. 5-second
   timeout. On any failure, falls back to the post-trigger text (fail-open).

A single Settings checkbox `Smart cleanup (prose mode)` controls the entire
feature. Default off. When off, `CleanupProcessor` returns its input
unchanged — no triggers, no LLM call, no extra latency.

Why this layering and not e.g. inlining into `PostProcessor`:

- `PostProcessor` does *format normalization* (whitespace, capitalization,
  user dictionary, URL shielding, mode-specific punctuation/keystrokes).
  `CleanupProcessor` does *semantic editing*. Different concerns, different
  failure modes, different testability — they belong in separate units.
- `PostProcessor` is already 371 lines and mode-aware. Adding optional
  network I/O to it would tangle pure-function logic with async failures.
- A separate component is cheaper to swap out or disable wholesale.

## Architecture

### File structure

```
Sources/vox/
├── Text/
│   ├── PostProcessor.swift       (existing — unchanged)
│   ├── CleanupProcessor.swift    (NEW — ~150 LOC)
│   └── TextInjector.swift        (existing — unchanged)
├── Util/
│   └── AppSettings.swift         (existing — add one Bool getter/setter)
├── App/
│   ├── MenuBarController.swift   (existing — wire CleanupProcessor into pipeline)
│   └── SettingsWindow.swift      (existing — add one checkbox)
└── ...

Tests/voxTests/
└── CleanupProcessorTests.swift   (NEW)
```

### Key types (Swift)

```swift
public struct CleanupProcessor {
    public typealias LLMCleanFunc = (_ input: String) async throws -> String

    public let mode: TranscriptionMode
    public let enabled: Bool
    public let llmCleaner: LLMCleanFunc?

    public init(
        mode: TranscriptionMode,
        enabled: Bool,
        llmCleaner: LLMCleanFunc? = nil
    )

    public func process(_ input: String) async -> String
}
```

The `llmCleaner` closure is dependency-injected so unit tests can supply
fakes. Production callers pass a closure that wraps a
`URLSession`-based call to `gpt-4o-mini`.

### Settings

```swift
extension AppSettings {
    static var smartCleanupEnabled: Bool { get / set }
    // backed by UserDefaults key "smartCleanupEnabled", default false
}
```

### LLM cleanup call

- Endpoint: `POST https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o-mini`
- Temperature: `0`
- max_tokens: `500`
- 5s request timeout
- Headers: `Authorization: Bearer <key>` (key from same provider as STT — no
  new Keychain entry).
- System prompt:
  > "You clean up dictated prose. Remove false starts, filler words (um,
  > uh), and self-corrections (where the speaker said one thing then
  > corrected to another — keep only the corrected version). Preserve all
  > factual content, names, numbers, URLs, and intentional repetition.
  > Output only the cleaned text, no explanation, no quotation marks."
- User message: the post-trigger text.

The cost-per-call is on the order of $0.0001 (≈250 tokens at gpt-4o-mini's
$0.15/M input + $0.60/M output rates). The latency is consistently sub-2s
in practice.

## Components

### 1. `applyTriggers(_ text: String) -> String`

Pure synchronous function. Three regex passes:

- `scratch that` / `delete that`: case-insensitive, anchored at the end of a
  sentence (followed by sentence terminator OR end-of-string), optionally
  preceded by sentence terminator. When matched, the matched phrase **and**
  the immediately preceding sentence are removed. Sentence boundaries =
  `[.!?]` followed by whitespace or end-of-string.
- `new paragraph` (case-insensitive, sentence-anchored): replaced with
  `\n\n`, with surrounding whitespace collapsed.
- `new line` (case-insensitive, sentence-anchored): replaced with `\n`.

Order: triggers are evaluated left-to-right in the input. Each trigger fires
at most once per match — applying triggers does not introduce text that
could re-match.

False-positive examples that must NOT trigger (covered by tests):

- `"I want to scratch that itch."` (no terminator after `that`)
- `"new paragraph format"` (no terminator after `paragraph`)
- `"new line of code"` (no terminator after `line`)

The trigger phrases are not configurable in v1.

### 2. `callLLMCleanup(_ text: String) async throws -> String`

A small wrapper around `URLSession.data(for:)`:

- Constructs the JSON body for `chat/completions` with the prompt and
  parameters above.
- Reads the API key from the same provider as the STT call (an
  `apiKeyProvider` closure passed in by the caller, mirroring the existing
  `OpenAITranscriber` pattern).
- 5s timeout via `URLRequest.timeoutInterval = 5.0`.
- Parses `choices[0].message.content`. Trims leading/trailing whitespace.
- Throws on non-2xx, malformed JSON, missing key, or transport error.
- Caller-side guard: if the trimmed result is shorter than 3 chars while
  input is ≥ 20 chars, treat as malformed (return input via fail-open).

### 3. `CleanupProcessor.process(_:)`

Orchestrator:

```
if !enabled                     → return input
let triggered = applyTriggers(input)
if mode == .command             → return triggered          (no LLM)
if triggered is empty/whitespace → return triggered          (skip LLM)
if llmCleaner is nil             → return triggered          (no cleaner injected)

do
    let cleaned = try await llmCleaner!(triggered)
    if cleaned suspiciously empty (see "small-output guard")
        log "Cleanup malformed response"
        return triggered
    return cleaned
catch
    log error to stderr
    return triggered
```

### 4. Pipeline integration in `MenuBarController`

Where `MenuBarController` currently does:

```swift
let raw = try await transcriber.transcribe(wav: wav, mode: mode)
let (text, suffixKeys) = PostProcessor(mode: mode).process(raw)
injector.paste(text, suffixKeys: suffixKeys, ...)
```

It will now do:

```swift
let raw = try await transcriber.transcribe(wav: wav, mode: mode)
let (text, suffixKeys) = PostProcessor(mode: mode).process(raw)

let cleaner = CleanupProcessor(
    mode: mode,
    enabled: AppSettings.smartCleanupEnabled,
    llmCleaner: AppSettings.smartCleanupEnabled ? makeLLMCleaner() : nil
)
let cleaned = await cleaner.process(text)

injector.paste(cleaned, suffixKeys: suffixKeys, ...)
```

`makeLLMCleaner()` is a small factory inside `MenuBarController` (or a
helper file) that returns the closure wired to `URLSession` and the
existing `apiKeyProvider`.

### 5. Settings UI in `SettingsWindow`

A single new checkbox in the existing layout:

> ☐ **Smart cleanup (prose mode)**
>   Removes false starts, filler words, and self-corrections via
>   gpt-4o-mini. Adds ~$0.0001 and ~1s latency per dictation.

Bound to `AppSettings.smartCleanupEnabled` (toggle reads/writes
`UserDefaults`).

## Data flow

```
User releases hotkey
   ↓
WAV bytes
   ↓
OpenAITranscriber.transcribe(wav, mode)              → raw STT text
   ↓
PostProcessor.process(raw, mode)                     → (formatted text, suffixKeys)
   ↓
CleanupProcessor(mode, enabled).process(formatted)
   ├─ enabled == false   → returns formatted unchanged
   ├─ applyTriggers(formatted)
   ├─ command mode       → returns triggered (no LLM)
   ├─ empty after trigger → returns triggered (skip LLM)
   └─ prose, non-empty   → llmCleaner(triggered) async, 5s timeout
       ├─ success         → cleaned text (or triggered if small-output guard fires)
       └─ error/timeout   → log + return triggered (fail-open)
   ↓
TextInjector.paste(cleaned, suffixKeys)
```

### Concrete example (prose, cleanup enabled)

```
User says     "Send to Marcus, actually no, send to Lena. Um, by 5pm.
               Scratch that. Make it 6pm."
STT          "Send to Marcus, actually no, send to Lena. Um, by 5 PM.
              Scratch that. Make it 6 PM."
PostProcessor "Send to Marcus, actually no, send to Lena. Um, by 5 PM.
              Scratch that. Make it 6 PM."
applyTriggers "Send to Marcus, actually no, send to Lena. Make it 6 PM."
LLM cleanup  "Send to Lena. Make it 6 PM."
TextInjector pastes "Send to Lena. Make it 6 PM."
```

## Error handling

| Failure mode                                  | Behavior                                                     |
|-----------------------------------------------|--------------------------------------------------------------|
| `smartCleanupEnabled == false`                | Pass-through. Triggers do not fire either.                   |
| Empty / whitespace input                      | Skip LLM. Return input.                                      |
| Missing OpenAI API key                        | Log `Cleanup: API key missing`. Return triggered text.       |
| HTTP 4xx/5xx                                  | Log `Cleanup HTTP <code>: <body[:200]>`. Return triggered.   |
| 5-second timeout                              | Log `Cleanup timeout`. Return triggered.                     |
| Malformed JSON / missing `choices[0].message` | Log `Cleanup malformed response`. Return triggered.          |
| Suspicious small output                       | Log `Cleanup malformed response`. Return triggered.          |
| Other transport error                         | Log `Cleanup transport: <err>`. Return triggered.            |

- No retries. Cleanup is single-shot per dictation.
- Logging is to stderr only. No user-facing notifications.

## Testing

`Tests/voxTests/CleanupProcessorTests.swift` covers (deterministic, no real
network):

1. **Trigger sentence wipes**
   - `"Send to Marcus. Scratch that. Send to Lena."` → `"Send to Lena."`
   - `"First. Second. Delete that."` → `"First."`
   - `"Scratch that."` alone → `""`
   - Case insensitive (`"SCRATCH THAT"`)
   - Punctuation tolerance (`"Scratch that,"`, `"scratch that ."`)

2. **Trigger paragraph / line**
   - `"Para one. New paragraph. Para two."` → `"Para one.\n\nPara two."`
   - `"Item one. New line. Item two."` → `"Item one.\nItem two."`
   - Multiple triggers in one utterance combine correctly

3. **Trigger false-positive guard**
   - `"I want to scratch that itch."` → unchanged
   - `"new paragraph format"` mid-sentence → unchanged
   - `"new line of code"` mid-sentence → unchanged

4. **Toggle off**
   - `enabled: false`, input contains trigger phrases → returned verbatim
   - Verify `llmCleaner` closure is never invoked

5. **Empty input**
   - `""` and `"   "` → returned unchanged
   - Verify `llmCleaner` is never invoked

6. **Command mode**
   - Triggers fire, LLM not called (verify via fake `llmCleaner` that asserts
     it is not invoked)

7. **Prose mode + injected fake LLM**
   - Fake returns `"clean output"` → CleanupProcessor returns `"clean output"`

8. **LLM throws**
   - Fake throws → CleanupProcessor returns post-trigger text (fail-open)

9. **Suspicious small output**
   - Fake returns `""` for input `"Hey there friend."` → return triggered
     text, not empty.

**No live integration tests against `gpt-4o-mini`**. Same discipline as
existing `OpenAITranscriber` (no live tests). The HTTP wiring is verified
manually before merge.

**Manual smoke test before merge**:

1. Enable Smart cleanup in Settings.
2. Dictate "I'll send the report to Marcus, actually no, to Lena, by 5 PM.
   Scratch that. By 6 PM."
3. Verify pasted text is approximately "I'll send the report to Lena by 6 PM."
4. Disable Smart cleanup; redo step 2; verify raw text is pasted (with the
   "Scratch that." literally present, since triggers are gated by the toggle
   too).
5. Confirm the existing prose dictations still work unchanged with the toggle off.

## Lifecycle / out-of-scope follow-ups

These are explicitly NOT part of this spec, but worth noting so they don't
get smuggled in:

- **Bypass hotkey** (Shift+Record = raw this dictation) — easy to layer in
  later if useful; v1 is just the Settings toggle.
- **Provider selectability** (Claude Haiku 4.5, etc.) — fixed to
  gpt-4o-mini in v1; switching is a new spec.
- **Per-app cleanup enable/disable** — out of scope.
- **Trigger phrase customization** — fixed v1 list of 3.
- **Cleanup usage cost in `UsageTracker`** — desirable but additive; can be
  separate small spec. Not blocking.
- **Arrow / modifier-combo suffix keys** (Ctrl+Right Arrow etc., raised by
  Andy mid-brainstorm) — different concern (command-mode keystroke
  injection), separate small spec.

## Decisions made during brainstorming

- **Hybrid LLM + hard triggers** chosen over LLM-only or trigger-only.
  Rationale: LLM handles natural-language self-correction the user cares
  about; deterministic triggers cover hard edits the LLM might miss.
- **Prose only for LLM call**. Command mode skips the LLM (`ls -la` is too
  short and structurally fragile to risk LLM rewriting), but command mode
  *does* benefit from "scratch that" sentence-undo, so triggers run there.
- **OpenAI `gpt-4o-mini`** chosen over Claude Haiku to reuse the existing
  OpenAI key. Switching providers is a single-file change and can be
  revisited.
- **Settings checkbox, default off**. Cleanup can silently corrupt prose
  when wrong; opt-in is safer than opt-out.
- **Three trigger phrases**: `scratch that` / `delete that`,
  `new paragraph`, `new line`. Anchored at sentence boundaries to
  minimize false positives. Larger trigger lists creep into LLM territory
  with worse precision.
- **Fail-open with 5s timeout, no retries**. STT output is the must-have,
  cleanup is the nice-to-have; the contract is "speak → text appears."
- **New file (`CleanupProcessor.swift`) over inlining into `PostProcessor`**
  — different concerns (semantic editing vs format normalization), different
  failure modes, different testability.
