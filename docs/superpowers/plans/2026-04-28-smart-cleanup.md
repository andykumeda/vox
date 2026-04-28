# Smart Cleanup (Prose Mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in post-STT cleanup pass that removes false starts, fillers, and self-corrections from prose dictations via gpt-4o-mini, plus a small set of deterministic trigger phrases ("scratch that", "new paragraph", "new line") that work in both prose and command modes.

**Architecture:** New `CleanupProcessor.swift` runs between `PostProcessor` and `TextInjector`. It applies regex triggers synchronously (gated by a Settings toggle) and, in prose mode only, delegates to an injectable `LLMCleanFunc` closure. Production wires that closure to OpenAI `/v1/chat/completions` with a 5s timeout and fail-open semantics. Tests inject fake closures.

**Tech Stack:** Swift 6 (Swift 5 mode), Foundation, XCTest, URLSession. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-28-smart-cleanup-design.md`

**Branch:** `feat/smart-cleanup` (already checked out at HEAD `e6d5550`).

**Discipline notes:**
- TDD applies to the pure-Swift logic (`CleanupProcessor`, `applyTriggers`, orchestrator). Each behavior gets a failing test before the implementation lands.
- The live HTTP wrapper (`makeLiveLLMCleaner`) is *not* unit-tested — same discipline as `OpenAITranscriber`. It's verified by manual smoke at the end.
- Pre-existing dirty files (`Resources/vox.entitlements`, `Sources/vox/STT/TranscriptionMode.swift`, `scripts/build-app.sh`) on this branch are unrelated to this work — leave them untouched.
- Use `--no-gpg-sign` on every commit (durable user preference).

---

## File Structure

```
Sources/vox/
├── Text/
│   ├── PostProcessor.swift           (existing, untouched)
│   ├── CleanupProcessor.swift        (NEW — ~180 LOC: triggers + orchestrator + LLM-closure type)
│   ├── CleanupLLMClient.swift        (NEW — ~80 LOC: live URLSession wrapper, factory function)
│   └── TextInjector.swift            (existing, untouched)
├── Util/
│   └── AppSettings.swift             (modify: add smartCleanupEnabled accessor)
└── App/
    ├── MenuBarController.swift       (modify: insert CleanupProcessor in transcribe Task)
    └── SettingsWindow.swift          (modify: add one checkbox)

Tests/voxTests/
└── CleanupProcessorTests.swift       (NEW — ~250 LOC)
```

Two new files in `Sources/vox/Text/` (not one) to keep `CleanupProcessor.swift` pure-and-testable: it has no `URLSession` import. The HTTP path lives in `CleanupLLMClient.swift` and is wired together in `MenuBarController`.

---

## Task 1: AppSettings — `smartCleanupEnabled`

**Files:**
- Modify: `Sources/vox/Util/AppSettings.swift` (around lines 27–46)

- [ ] **Step 1: Locate the existing settings block**

Run: `grep -n "forceProseKey\|forceProseMode" Sources/vox/Util/AppSettings.swift`

Expected: matches at lines `30: private static let forceProseKey = "forceProseMode"` and `48-51: forceProseMode`.

- [ ] **Step 2: Add the new key constant**

Edit `Sources/vox/Util/AppSettings.swift`. Find:

```swift
    private static let keepKey = "keepTranscriptionOnClipboard"
    private static let modelKey = "transcriptionModel"
    private static let forceProseKey = "forceProseMode"
```

Replace with:

```swift
    private static let keepKey = "keepTranscriptionOnClipboard"
    private static let modelKey = "transcriptionModel"
    private static let forceProseKey = "forceProseMode"
    private static let smartCleanupKey = "smartCleanupEnabled"
```

- [ ] **Step 3: Add the accessor**

Find:

```swift
    static var forceProseMode: Bool {
        get { UserDefaults.standard.bool(forKey: forceProseKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceProseKey) }
    }
```

Append immediately after (still inside the `enum AppSettings` block):

```swift
    static var smartCleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: smartCleanupKey) }
        set { UserDefaults.standard.set(newValue, forKey: smartCleanupKey) }
    }
```

- [ ] **Step 4: Verify the project still builds**

Run: `swift build 2>&1 | tail -20`
Expected: build succeeds (no errors). May see warnings unrelated to this change — acceptable.

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Util/AppSettings.swift
git commit --no-gpg-sign -m "feat(settings): add smartCleanupEnabled toggle (default false)"
```

---

## Task 2: CleanupProcessor skeleton + toggle-off test

**Files:**
- Create: `Sources/vox/Text/CleanupProcessor.swift`
- Create: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/voxTests/CleanupProcessorTests.swift`:

```swift
import XCTest
@testable import vox

final class CleanupProcessorTests: XCTestCase {

    // MARK: - Toggle off

    func testToggleOffReturnsInputUnchanged() async {
        let proc = CleanupProcessor(mode: .prose, enabled: false, llmCleaner: nil)
        let result = await proc.process("Send to Marcus. Scratch that. Send to Lena.")
        XCTAssertEqual(result, "Send to Marcus. Scratch that. Send to Lena.")
    }

    func testToggleOffNeverInvokesLLMCleaner() async {
        var called = false
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            called = true
            return ""
        }
        let proc = CleanupProcessor(mode: .prose, enabled: false, llmCleaner: cleaner)
        _ = await proc.process("Anything at all.")
        XCTAssertFalse(called, "llmCleaner must not be invoked when enabled is false")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: FAIL with `cannot find 'CleanupProcessor' in scope`.

- [ ] **Step 3: Create the skeleton**

Create `Sources/vox/Text/CleanupProcessor.swift`:

```swift
import Foundation

public struct CleanupProcessor {
    public typealias LLMCleanFunc = @Sendable (_ input: String) async throws -> String

    public let mode: TranscriptionMode
    public let enabled: Bool
    public let llmCleaner: LLMCleanFunc?

    public init(
        mode: TranscriptionMode,
        enabled: Bool,
        llmCleaner: LLMCleanFunc? = nil
    ) {
        self.mode = mode
        self.enabled = enabled
        self.llmCleaner = llmCleaner
    }

    public func process(_ input: String) async -> String {
        guard enabled else { return input }
        return input  // triggers + LLM added in subsequent tasks
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Text/CleanupProcessor.swift Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "feat(text): add CleanupProcessor skeleton with toggle-off behavior"
```

---

## Task 3: Trigger — `scratch that` / `delete that`

Wipes the immediately preceding sentence when "scratch that" or "delete that" appears as its own sentence.

**Files:**
- Modify: `Sources/vox/Text/CleanupProcessor.swift`
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/voxTests/CleanupProcessorTests.swift` inside the `final class CleanupProcessorTests` body:

```swift
    // MARK: - Trigger: scratch that / delete that

    private func makeProseProc() -> CleanupProcessor {
        CleanupProcessor(mode: .prose, enabled: true, llmCleaner: { $0 })
    }

    func testScratchThatWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("Send to Marcus. Scratch that. Send to Lena.")
        XCTAssertEqual(result, "Send to Lena.")
    }

    func testDeleteThatWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("First. Second. Delete that.")
        XCTAssertEqual(result, "First.")
    }

    func testScratchThatAtStartReturnsEmpty() async {
        let proc = makeProseProc()
        let result = await proc.process("Scratch that.")
        XCTAssertEqual(result, "")
    }

    func testScratchThatCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello there. SCRATCH THAT. Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }

    func testScratchThatTolerantOfTrailingComma() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello. Scratch that, Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }
```

The `makeProseProc()` helper supplies an identity `llmCleaner` so the orchestrator can pass through to whatever `applyTriggers` returns once Task 7 wires it in. For Tasks 3–6 the `process()` body does not yet call the LLM, so the closure isn't actually invoked — these tests pass on the synchronous path. (When Task 7 wires the LLM in, identity preserves the trigger output.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -30`
Expected: 5 new tests FAIL — they all return the input unchanged because triggers aren't implemented yet.

- [ ] **Step 3: Add the trigger logic**

In `Sources/vox/Text/CleanupProcessor.swift`, replace the entire body of the `process` method and add private helpers. The full updated file body becomes:

```swift
import Foundation

public struct CleanupProcessor {
    public typealias LLMCleanFunc = @Sendable (_ input: String) async throws -> String

    public let mode: TranscriptionMode
    public let enabled: Bool
    public let llmCleaner: LLMCleanFunc?

    public init(
        mode: TranscriptionMode,
        enabled: Bool,
        llmCleaner: LLMCleanFunc? = nil
    ) {
        self.mode = mode
        self.enabled = enabled
        self.llmCleaner = llmCleaner
    }

    public func process(_ input: String) async -> String {
        guard enabled else { return input }
        return applyTriggers(input)
    }

    // MARK: - Triggers

    /// Runs the three trigger phrases over the input. Pure synchronous function.
    func applyTriggers(_ input: String) -> String {
        let sentences = splitSentences(input)
        var output: [String] = []

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if isScratchThatTrigger(trimmed) {
                if !output.isEmpty {
                    output.removeLast()
                }
                continue
            }
            if isNewParagraphTrigger(trimmed) {
                output.append("\n\n")
                continue
            }
            if isNewLineTrigger(trimmed) {
                output.append("\n")
                continue
            }
            output.append(sentence)
        }

        return joinSentences(output)
    }

    private func splitSentences(_ input: String) -> [String] {
        var sentences: [String] = []
        let range = input.startIndex..<input.endIndex
        input.enumerateSubstrings(in: range, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring, !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty && !input.isEmpty {
            sentences = [input]
        }
        return sentences
    }

    private func joinSentences(_ pieces: [String]) -> String {
        var result = ""
        for piece in pieces {
            if piece == "\n\n" || piece == "\n" {
                // Strip trailing whitespace from previous sentence, then append the break.
                while result.last?.isWhitespace == true {
                    result.removeLast()
                }
                result.append(piece)
                continue
            }
            // Sentence enumerator returns sentences with trailing whitespace already.
            result.append(piece)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isScratchThatTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)(scratch|delete) that[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isNewParagraphTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)new paragraph[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isNewLineTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)new line[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -30`
Expected: all CleanupProcessorTests PASS (7 tests total: 2 from Task 2 + 5 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Text/CleanupProcessor.swift Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "feat(text): CleanupProcessor 'scratch that'/'delete that' trigger wipes preceding sentence"
```

---

## Task 4: Trigger — `new paragraph`

The trigger code already exists from Task 3 (`isNewParagraphTrigger` is wired into `applyTriggers`). Tests verify it behaves correctly.

**Files:**
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `CleanupProcessorTests`:

```swift
    // MARK: - Trigger: new paragraph

    func testNewParagraphInsertsDoubleNewline() async {
        let proc = makeProseProc()
        let result = await proc.process("Para one. New paragraph. Para two.")
        XCTAssertEqual(result, "Para one.\n\nPara two.")
    }

    func testNewParagraphCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("Header. NEW PARAGRAPH. Body.")
        XCTAssertEqual(result, "Header.\n\nBody.")
    }

    func testNewParagraphMultipleInOneUtterance() async {
        let proc = makeProseProc()
        let result = await proc.process("First. New paragraph. Second. New paragraph. Third.")
        XCTAssertEqual(result, "First.\n\nSecond.\n\nThird.")
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: PASS (the implementation from Task 3 already handles this).

If they fail, the most likely cause is that `joinSentences` is mishandling sentence-trailing whitespace — inspect the actual output and adjust `joinSentences` to strip whitespace correctly.

- [ ] **Step 3: Commit**

```bash
git add Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "test(text): cover 'new paragraph' trigger in CleanupProcessor"
```

---

## Task 5: Trigger — `new line`

Same shape as Task 4. Implementation already in place.

**Files:**
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append:

```swift
    // MARK: - Trigger: new line

    func testNewLineInsertsSingleNewline() async {
        let proc = makeProseProc()
        let result = await proc.process("Item one. New line. Item two.")
        XCTAssertEqual(result, "Item one.\nItem two.")
    }

    func testNewLineCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("A. NEW LINE. B.")
        XCTAssertEqual(result, "A.\nB.")
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "test(text): cover 'new line' trigger in CleanupProcessor"
```

---

## Task 6: Trigger false-positive guards

Triggers must not fire mid-sentence. The full-sentence regex in Task 3 enforces this; tests prove it.

**Files:**
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append:

```swift
    // MARK: - Trigger false positives

    func testScratchThatItchDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "I want to scratch that itch."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testNewParagraphFormatDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "We need a new paragraph format for this document."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testNewLineOfCodeDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "Add a new line of code to the function."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testDeleteThatBugDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "We should delete that bug from the queue."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: PASS. The triggers' `^...$` anchoring against a single-sentence string keeps mid-sentence occurrences from matching.

If a test fails, inspect which sentence the enumerator produced — `enumerateSubstrings(.bySentences)` may have surprised us. Adjust the regex to require word boundaries around the keyword if so.

- [ ] **Step 3: Commit**

```bash
git add Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "test(text): false-positive guards for cleanup triggers"
```

---

## Task 7: Process orchestrator — mode, empty, LLM injection

Wire the LLM call into `process()`. Triggers run first (already implemented). For prose with non-empty post-trigger text, call the injected `llmCleaner`. Command mode and empty inputs skip the LLM.

**Files:**
- Modify: `Sources/vox/Text/CleanupProcessor.swift`
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `CleanupProcessorTests`:

```swift
    // MARK: - Orchestrator

    func testProseInvokesLLMWithTriggeredText() async {
        var receivedInput: String?
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            receivedInput = input
            return "[cleaned] \(input)"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("First. Scratch that. Second.")
        XCTAssertEqual(receivedInput, "Second.")
        XCTAssertEqual(result, "[cleaned] Second.")
    }

    func testCommandModeSkipsLLM() async {
        var called = false
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            called = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("ls -la. Scratch that. ls -lh.")
        XCTAssertFalse(called)
        XCTAssertEqual(result, "ls -lh.")
    }

    func testEmptyInputSkipsLLM() async {
        var called = false
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            called = true
            return "noop"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("")
        XCTAssertFalse(called)
        XCTAssertEqual(result, "")
    }

    func testWhitespaceOnlyInputSkipsLLM() async {
        var called = false
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            called = true
            return "noop"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("   \n  ")
        XCTAssertFalse(called)
        XCTAssertEqual(result, "")
    }

    func testNoLLMInjectedSkipsLLM() async {
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: nil)
        let result = await proc.process("Hello world.")
        XCTAssertEqual(result, "Hello world.")
    }
```

Note: the existing `makeProseProc()` helper from Task 3 wires an identity `llmCleaner`, so prior tests still pass after the orchestrator wires the LLM in (identity returns the triggered text unchanged).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -30`
Expected: 5 new tests FAIL — `process` currently ignores the `llmCleaner` closure entirely.

- [ ] **Step 3: Update `process` to invoke the LLM**

Replace the `process` method body in `Sources/vox/Text/CleanupProcessor.swift` with:

```swift
    public func process(_ input: String) async -> String {
        guard enabled else { return input }
        let triggered = applyTriggers(input)

        if mode == .command { return triggered }

        let trimmed = triggered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        guard let cleaner = llmCleaner else { return triggered }

        do {
            let cleaned = try await cleaner(triggered)
            return cleaned
        } catch {
            FileHandle.standardError.write(Data("Cleanup error: \(error)\n".utf8))
            return triggered
        }
    }
```

(The fail-open `catch` block is already in place here — Task 8 adds the dedicated test for it. Task 9 layers in the small-output guard.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -30`
Expected: ALL CleanupProcessorTests PASS (now ~17 total).

If `testProseInvokesLLMWithTriggeredText` fails because the captured input contains a trailing newline or extra space, that means `joinSentences` left whitespace at the end. Re-examine its trim and adjust until `applyTriggers("First. Scratch that. Second.") == "Second."` exactly.

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Text/CleanupProcessor.swift Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "feat(text): CleanupProcessor orchestrator wires triggers + LLM with fail-open"
```

---

## Task 8: LLM error → fail-open

The fail-open path is already implemented in Task 7's `process` method. This task adds the explicit test.

**Files:**
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing test**

Append:

```swift
    // MARK: - Fail-open

    func testLLMThrowsReturnsTriggeredText() async {
        struct DummyError: Error {}
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in throw DummyError() }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hello. Scratch that. World.")
        XCTAssertEqual(result, "World.")
    }

    func testLLMHTTPErrorReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            throw NSError(domain: "test", code: 500, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Goodbye world.")
        XCTAssertEqual(result, "Goodbye world.")
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: PASS. Task 7 already implemented the catch.

- [ ] **Step 3: Commit**

```bash
git add Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "test(text): cover CleanupProcessor LLM-throw fail-open path"
```

---

## Task 9: Suspicious-small-output guard

If the LLM returns a string suspiciously shorter than the input (likely a malformed completion, e.g. empty or a stray punctuation mark), treat it as an error and return the post-trigger text instead. This avoids silent total content loss.

**Files:**
- Modify: `Sources/vox/Text/CleanupProcessor.swift`
- Modify: `Tests/voxTests/CleanupProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `CleanupProcessorTests`:

```swift
    // MARK: - Small-output guard

    func testLLMEmptyOutputReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "" }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hey there friend.")
        XCTAssertEqual(result, "Hey there friend.")
    }

    func testLLMTinyOutputReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "." }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("This is a complete sentence with several words.")
        XCTAssertEqual(result, "This is a complete sentence with several words.")
    }

    func testLLMShortInputAllowsShortOutput() async {
        // If input is short, a short output is fine — guard only kicks in when input is long.
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "Hi." }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hi.")
        XCTAssertEqual(result, "Hi.")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: the first two tests FAIL (LLM output is currently passed through verbatim). Third test PASSES already.

- [ ] **Step 3: Add the guard**

In `Sources/vox/Text/CleanupProcessor.swift`, replace the `do { ... } catch { ... }` block inside `process` with:

```swift
        do {
            let cleaned = try await cleaner(triggered)
            let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            // Suspicious-small-output guard: if the LLM returns far less than we sent,
            // treat it as a malformed completion and fail open. Threshold tuned to allow
            // legitimate aggressive cleanups (e.g. "Hi." -> "Hi.") while catching empty
            // or near-empty completions for normal-length input.
            if triggered.count >= 20 && trimmedCleaned.count < 3 {
                FileHandle.standardError.write(Data("Cleanup malformed response (length \(trimmedCleaned.count) < 3 for input length \(triggered.count))\n".utf8))
                return triggered
            }
            return trimmedCleaned
        } catch {
            FileHandle.standardError.write(Data("Cleanup error: \(error)\n".utf8))
            return triggered
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupProcessorTests 2>&1 | tail -20`
Expected: all CleanupProcessorTests PASS (~22 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/Text/CleanupProcessor.swift Tests/voxTests/CleanupProcessorTests.swift
git commit --no-gpg-sign -m "feat(text): CleanupProcessor guards against suspiciously small LLM output"
```

---

## Task 10: Live LLM client — `CleanupLLMClient.swift`

A factory that returns a `CleanupProcessor.LLMCleanFunc` closure backed by URLSession against OpenAI `/v1/chat/completions`. Not unit-tested (mirrors `OpenAITranscriber`'s discipline). Verified by Task 13's manual smoke.

**Files:**
- Create: `Sources/vox/Text/CleanupLLMClient.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

public enum CleanupLLMError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(Int, String)
    case malformedResponse
    case transportError(Error)

    public var description: String {
        switch self {
        case .missingAPIKey: return "Cleanup: OPENAI_API_KEY missing"
        case .httpError(let code, let body): return "Cleanup HTTP \(code): \(body)"
        case .malformedResponse: return "Cleanup malformed response"
        case .transportError(let e): return "Cleanup transport: \(e.localizedDescription)"
        }
    }
}

/// Returns a closure suitable for `CleanupProcessor.llmCleaner` that calls
/// OpenAI `/v1/chat/completions` with `gpt-4o-mini`. The closure throws
/// `CleanupLLMError` on every failure path — `CleanupProcessor` catches them
/// and falls back to the post-trigger text.
public func makeLiveLLMCleaner(
    apiKeyProvider: @escaping () -> String?
) -> CleanupProcessor.LLMCleanFunc {
    return { input in
        guard let raw = apiKeyProvider() else {
            throw CleanupLLMError.missingAPIKey
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CleanupLLMError.missingAPIKey }

        let systemPrompt = """
        You clean up dictated prose. Remove false starts, filler words (um, uh), \
        and self-corrections (where the speaker said one thing then corrected to \
        another — keep only the corrected version). Preserve all factual \
        content, names, numbers, URLs, and intentional repetition. Output only \
        the cleaned text, no explanation, no quotation marks.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "max_tokens": 500,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": input],
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 5.0

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CleanupLLMError.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CleanupLLMError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let truncated = bodyText.count > 200 ? String(bodyText.prefix(200)) : bodyText
            throw CleanupLLMError.httpError(http.statusCode, truncated)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CleanupLLMError.malformedResponse
        }
        return content
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/vox/Text/CleanupLLMClient.swift
git commit --no-gpg-sign -m "feat(text): add live OpenAI cleanup HTTP client (gpt-4o-mini, 5s timeout)"
```

---

## Task 11: SettingsWindow — checkbox

Add the toggle to the existing Settings window.

**Files:**
- Modify: `Sources/vox/App/SettingsWindow.swift`

- [ ] **Step 1: Locate the existing forceProseMode checkbox in SettingsWindow**

Run: `grep -n "forceProseMode\|forceProse" Sources/vox/App/SettingsWindow.swift`

Expected: 3-5 matches. Identify the checkbox declaration and the layout call that adds it (typically `addArrangedSubview` or `setSubviews`).

- [ ] **Step 2: Add a parallel checkbox**

Find the existing forceProseMode block. It will look approximately like:

```swift
let forceProseCheckbox = NSButton(
    checkboxWithTitle: "Force prose mode for all dictations",
    target: self,
    action: #selector(toggleForceProse(_:))
)
forceProseCheckbox.state = AppSettings.forceProseMode ? .on : .off
```

Immediately after that block (still in the same scope), append:

```swift
let smartCleanupCheckbox = NSButton(
    checkboxWithTitle: "Smart cleanup (prose mode): remove false starts and self-corrections via gpt-4o-mini",
    target: self,
    action: #selector(toggleSmartCleanup(_:))
)
smartCleanupCheckbox.state = AppSettings.smartCleanupEnabled ? .on : .off
smartCleanupCheckbox.toolTip = "Adds ~$0.0001 and ~1s latency per dictation. Triggers ('scratch that', 'new paragraph', 'new line') also activate when enabled."
```

Then add the checkbox to the same view container the `forceProseCheckbox` is added to. If you find the line `stack.addArrangedSubview(forceProseCheckbox)` (or equivalent), add `stack.addArrangedSubview(smartCleanupCheckbox)` immediately after it.

- [ ] **Step 3: Add the action method**

Find the existing `toggleForceProse` method:

```swift
@objc private func toggleForceProse(_ sender: NSButton) {
    AppSettings.forceProseMode = (sender.state == .on)
}
```

Immediately after it, append:

```swift
@objc private func toggleSmartCleanup(_ sender: NSButton) {
    AppSettings.smartCleanupEnabled = (sender.state == .on)
}
```

- [ ] **Step 4: Build to verify**

Run: `swift build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "feat(settings): add Smart Cleanup toggle to SettingsWindow"
```

---

## Task 12: MenuBarController — wire `CleanupProcessor` into pipeline

Insert the cleanup pass between `PostProcessor.process(raw)` and `injector.paste(...)` in the transcribe `Task`.

**Files:**
- Modify: `Sources/vox/App/MenuBarController.swift` (around lines 297–325)

- [ ] **Step 1: Locate the transcribe Task**

Run: `grep -n "PostProcessor(mode: mode).process\|injector.paste" Sources/vox/App/MenuBarController.swift`

Expected: matches at lines around 303 (`PostProcessor(mode: mode).process(raw)`) and 315 (`injector.paste(...)`).

- [ ] **Step 2: Find the apiKeyProvider used by `transcriber`**

Run: `grep -n "OpenAITranscriber\|apiKeyProvider" Sources/vox/App/MenuBarController.swift`

Expected: locate the `transcriber` lazy property (around line 47–60) and how its `apiKeyProvider` closure resolves the OpenAI key (likely via `KeychainStore`). Note the exact closure used so we reuse it for cleanup.

- [ ] **Step 3: Add a stored cleanup-cleaner factory next to `transcriber`**

In the property block where `transcriber` is declared (around lines 45–60), after the `transcriber` lazy property, add:

```swift
    private lazy var liveLLMCleaner: CleanupProcessor.LLMCleanFunc = makeLiveLLMCleaner(
        apiKeyProvider: { KeychainStore.shared.openAIKey }
    )
```

If the `OpenAITranscriber`'s `apiKeyProvider` uses a different expression than `KeychainStore.shared.openAIKey`, copy *exactly that expression* into the closure body so cleanup and STT use the identical key resolution path.

- [ ] **Step 4: Insert the cleanup call into the Task body**

Find:

```swift
                let raw = try await self.transcriber.transcribe(wav: wav, mode: mode)
                dlog("raw=\(raw)")
                let processed = await MainActor.run {
                    PostProcessor(mode: mode).process(raw)
                }
                let wordCount = processed.text.split(whereSeparator: { $0.isWhitespace }).count
```

Replace with:

```swift
                let raw = try await self.transcriber.transcribe(wav: wav, mode: mode)
                dlog("raw=\(raw)")
                let processed = await MainActor.run {
                    PostProcessor(mode: mode).process(raw)
                }

                let cleanupEnabled = AppSettings.smartCleanupEnabled
                let cleaner = CleanupProcessor(
                    mode: mode,
                    enabled: cleanupEnabled,
                    llmCleaner: cleanupEnabled ? self.liveLLMCleaner : nil
                )
                let cleanedText = await cleaner.process(processed.text)
                dlog("cleaned=\(cleanedText)")

                let wordCount = cleanedText.split(whereSeparator: { $0.isWhitespace }).count
```

Then, in the `await MainActor.run { ... }` block immediately below, find:

```swift
                    if processed.text.isEmpty {
                        pasteDelay = 0
                    } else {
                        self.injector.paste(processed.text, keepOnClipboard: AppSettings.keepTranscriptionOnClipboard)
                        pasteDelay = 0.2
                    }
```

Replace with:

```swift
                    if cleanedText.isEmpty {
                        pasteDelay = 0
                    } else {
                        self.injector.paste(cleanedText, keepOnClipboard: AppSettings.keepTranscriptionOnClipboard)
                        pasteDelay = 0.2
                    }
```

The `processed.suffixKeys` continues to be sourced from PostProcessor's output unchanged (cleanup never produces suffix keys).

- [ ] **Step 5: Build and run all existing tests**

```bash
swift build 2>&1 | tail -20
swift test 2>&1 | tail -20
```

Expected: build succeeds; all existing test suites still pass (PostProcessorTests, DictionaryStoreTests, etc.) plus the new CleanupProcessorTests.

- [ ] **Step 6: Commit**

```bash
git add Sources/vox/App/MenuBarController.swift
git commit --no-gpg-sign -m "feat(app): wire CleanupProcessor into transcribe pipeline (after PostProcessor)"
```

---

## Task 13: Manual smoke verification

Live end-to-end test against real OpenAI gpt-4o-mini. No code changes; ends with a brief findings note in `docs/`.

**Files:**
- (Optional) Modify: `docs/superpowers/specs/2026-04-28-smart-cleanup-design.md` — append a short "Implementation verified" line

- [ ] **Step 1: Build the app**

```bash
./scripts/build-app.sh 2>&1 | tail -10
```

Expected: app bundle built without errors. (If `build-app.sh` has unrelated WIP modifications on this branch from earlier work, either stash or accept them — they are not the cleanup feature's concern. They were noted in the plan header.)

- [ ] **Step 2: Launch Vox and enable Smart cleanup**

Open the built app, enter Settings, tick "Smart cleanup (prose mode)". Close Settings.

- [ ] **Step 3: Smoke — self-correction**

Hold record hotkey, dictate:

> "I'll send the report to Marcus, actually no, to Lena, by 5 PM. Scratch that. By 6 PM."

Release. Expected pasted text approximately: `"I'll send the report to Lena by 6 PM."` (LLM removes the self-correction; trigger removes the "by 5 PM" sentence; LLM keeps "By 6 PM").

If pasted text is the raw verbatim, check the menu bar log / stderr for any `Cleanup` lines indicating an error.

- [ ] **Step 4: Smoke — disabled toggle = raw**

In Settings, untick "Smart cleanup". Re-dictate the same utterance. Expected: full verbatim is pasted, including "actually no", "Scratch that.", and both "5 PM"/"6 PM".

- [ ] **Step 5: Smoke — paragraph trigger**

Re-enable Smart cleanup. Dictate:

> "Item one is the design. New paragraph. Item two is the implementation."

Expected pasted text: `"Item one is the design.\n\nItem two is the implementation."` (visible as two paragraphs in any text field).

- [ ] **Step 6: Smoke — command-mode triggers, no LLM**

Switch to command mode (mode-toggle hotkey). Dictate:

> "ls dash la. Scratch that. ls dash lh."

Expected pasted text: `"ls -lh"` (the first command sentence is wiped by the trigger; LLM is *not* called in command mode, but `PostProcessor` already performs the dash-to-`-` mapping).

- [ ] **Step 7: Smoke — silence → silence-gate skips cleanup**

Hold record, stay silent ~3 seconds, release. Expected: nothing is pasted (the existing silence gate in `MenuBarController` short-circuits before transcription, so cleanup never runs).

- [ ] **Step 8: Append a verification note to the spec**

In `docs/superpowers/specs/2026-04-28-smart-cleanup-design.md`, append a final section:

```markdown
## Implementation verified — 2026-04-28

Smoke tests passed:
- Self-correction removed by gpt-4o-mini
- "Scratch that" wipes preceding sentence
- "New paragraph" inserts double newline
- Command mode applies triggers but skips LLM
- Toggle off restores raw verbatim behavior
- Silence gate continues to short-circuit the pipeline before cleanup

(Adjust the bullets to reflect what actually passed; if any failed, document the failure and link the follow-up issue.)
```

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/specs/2026-04-28-smart-cleanup-design.md
git commit --no-gpg-sign -m "docs: record Smart Cleanup smoke verification"
```

---

## Self-review notes

**Spec coverage (every spec section maps to a task):**

- "New `CleanupProcessor` runs after `PostProcessor`" → Tasks 2, 7, 12
- "Three deterministic triggers" → Tasks 3, 4, 5
- "Triggers anchored at sentence boundaries; minimal false positives" → Task 6
- "LLM cleanup pass via gpt-4o-mini, 5s timeout" → Task 10
- "Single Settings checkbox `smartCleanupEnabled`, default false" → Tasks 1, 11
- "Pipeline: STT → PostProcessor → CleanupProcessor → TextInjector" → Task 12
- "Fail-open on any error/timeout" → Tasks 7, 8
- "Suspicious-small-output guard" → Task 9
- "Triggers run in both prose and command modes when enabled" → Task 7 (`testCommandModeSkipsLLM` confirms triggers fire, LLM doesn't)
- "Tests cover all listed cases (toggle off, empty, command mode, fake LLM, throw, small output, false positives)" → Tasks 2, 3, 4, 5, 6, 7, 8, 9
- "Manual smoke before merge" → Task 13

**No placeholders** — every code step shows concrete code; every test step shows concrete assertions; no "implement appropriate X" or "similar to Task N".

**Type consistency** — `LLMCleanFunc` is defined once in Task 2 and reused identically in every later task (Tasks 7, 8, 9, 10, 12). `applyTriggers` signature is set in Task 3 and unchanged thereafter. `process(_:)` signature stays `(String) async -> String` throughout.

**Pipeline insertion point** — Task 12 is the only task that touches `MenuBarController.swift`, and it operates strictly between the `PostProcessor.process` call and the `injector.paste` call. The `processed.suffixKeys` carry through unchanged, preserving existing behavior.
