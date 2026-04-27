# User Dictionary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `fixCommonMisfires` map in `PostProcessor` with a user-editable dictionary that applies token-based literal substitutions in both command and prose modes, persisted as JSON at `~/Library/Application Support/Vox/dictionary.json`, with built-in defaults seeded on first launch and merged on app upgrade.

**Architecture:** A `DictionaryStore` singleton owns the JSON file (load/seed/save/watch). A pure `DictionaryMatcher` does whitespace-tokenized literal matching. `PostProcessor` calls the matcher as the last pipeline step in each mode, fed by an injected provider closure (default = `DictionaryStore.shared.entries`). A SwiftUI section in Settings provides an in-app editor; a `DispatchSource` file watcher keeps in-memory state in sync with external edits.

**Tech Stack:** Swift 5.x, Swift Package Manager (`swift build` / `swift test`), XCTest, SwiftUI, AppKit, Foundation `JSONEncoder`/`JSONDecoder`, `DispatchSource` for file watching.

**Spec:** `docs/superpowers/specs/2026-04-27-user-dictionary-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `Sources/vox/Util/DictionaryEntry.swift` | `Codable` value type for a single entry + `Scope` enum. |
| `Sources/vox/Util/DictionaryMatcher.swift` | Pure function: apply a list of entries to an input string, scoped to a mode. No I/O, no state. |
| `Sources/vox/Util/DictionaryStore.swift` | Singleton; owns disk I/O, seed-merge, file watcher, in-memory `entries`. Publishes changes for SwiftUI. |
| `Sources/vox/Util/DictionaryDefaults.swift` | The `bundledDefaults: [DictionaryEntry]` array. Kept separate so the seed list is easy to read and audit. |
| `Tests/voxTests/DictionaryMatcherTests.swift` | Unit tests for the matcher. Pure-function, deterministic. |
| `Tests/voxTests/DictionaryStoreTests.swift` | Unit tests for load/seed/save with a tempdir-scoped store. |

### Modified files

| Path | Change |
|---|---|
| `Sources/vox/Text/PostProcessor.swift` | Add `dictionaryProvider` init parameter; replace `fixCommonMisfires` call with `applyDictionary`; delete `misfireReplacements` array and `fixCommonMisfires`/`misfireReplacements` static defs. |
| `Sources/vox/App/SettingsWindow.swift` | Add Dictionary section (Add, Reveal in Finder, table, edit sheet). |
| `Tests/voxTests/PostProcessorTests.swift` | Convert `testCommandFixes*` misfire tests to inject explicit dictionary providers; add new tests for prose-mode dictionary, scope filter, sort order, empty replacement. |

---

## Conventions

- **Working directory:** `/Users/andy/Dev/vox`. All paths below assume this prefix.
- **Build:** `swift build` from repo root.
- **Test:** `swift test` from repo root. Filter with `--filter <ClassName>`.
- **Commits:** No GPG signing required (`git commit --no-gpg-sign`). Conventional-commits-ish but free-form is fine — match the repo's existing terse imperative style (e.g., `Add user-dictionary design spec`).
- **No comments** unless they explain non-obvious WHY. Code style follows existing files (4-space indent, Swift API design guidelines).

---

## Task 1: `DictionaryEntry` value type

**Files:**
- Create: `Sources/vox/Util/DictionaryEntry.swift`

- [ ] **Step 1.1: Write the file**

```swift
import Foundation

public enum Scope: String, Codable, CaseIterable, Sendable {
    case command
    case prose
    case both
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var spoken: String
    public var replacement: String
    public var mode: Scope
    public var startsWith: Bool
    public var caseInsensitive: Bool
    public var enabled: Bool
    public var isBuiltIn: Bool

    public init(
        id: String,
        spoken: String,
        replacement: String,
        mode: Scope,
        startsWith: Bool = false,
        caseInsensitive: Bool = true,
        enabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.spoken = spoken
        self.replacement = replacement
        self.mode = mode
        self.startsWith = startsWith
        self.caseInsensitive = caseInsensitive
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }
}
```

- [ ] **Step 1.2: Verify the package compiles**

Run: `swift build`
Expected: `Build complete!` with no errors related to the new file. Pre-existing `try? h.seekToEnd()` warning may still appear.

- [ ] **Step 1.3: Commit**

```bash
git add Sources/vox/Util/DictionaryEntry.swift
git commit --no-gpg-sign -m "Add DictionaryEntry + Scope value types"
```

---

## Task 2: `DictionaryMatcher` — token-based literal substitution

**Files:**
- Create: `Sources/vox/Util/DictionaryMatcher.swift`
- Test: `Tests/voxTests/DictionaryMatcherTests.swift`

This task implements the substitution algorithm in isolation as a pure function, with tests written first.

- [ ] **Step 2.1: Write the failing test file**

Create `Tests/voxTests/DictionaryMatcherTests.swift`:

```swift
import XCTest
@testable import vox

final class DictionaryMatcherTests: XCTestCase {

    private func entry(
        _ spoken: String, _ replacement: String,
        mode: Scope = .command, startsWith: Bool = false,
        caseInsensitive: Bool = true, enabled: Bool = true
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: "test-\(UUID().uuidString)",
            spoken: spoken, replacement: replacement,
            mode: mode, startsWith: startsWith,
            caseInsensitive: caseInsensitive, enabled: enabled
        )
    }

    func testReplacesSingleTokenMatch() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -l")
    }

    func testDoesNotMatchInsideLongerToken() {
        // "-shell" must not match inside "--shell".
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "usermod --shell /bin/zsh",
            scope: .command
        )
        XCTAssertEqual(result, "usermod --shell /bin/zsh")
    }

    func testStartsWithAnchorsAtTokenZero() {
        let result = DictionaryMatcher.apply(
            entries: [entry("hello,", "ls", startsWith: true)],
            to: "hello, -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }

    func testStartsWithDoesNotMatchMidString() {
        let result = DictionaryMatcher.apply(
            entries: [entry("hello,", "ls", startsWith: true)],
            to: "echo hello, world",
            scope: .command
        )
        XCTAssertEqual(result, "echo hello, world")
    }

    func testCaseInsensitiveByDefault() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose)],
            to: "running VOX today",
            scope: .prose
        )
        XCTAssertEqual(result, "running Vox today")
    }

    func testCaseSensitiveWhenFlagOff() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose, caseInsensitive: false)],
            to: "running VOX today",
            scope: .prose
        )
        XCTAssertEqual(result, "running VOX today")
    }

    func testScopeCommandSkipsProseEntries() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose)],
            to: "vox status",
            scope: .command
        )
        XCTAssertEqual(result, "vox status")
    }

    func testScopeBothFiresInBothModes() {
        let e = entry("foo", "bar", mode: .both)
        XCTAssertEqual(
            DictionaryMatcher.apply(entries: [e], to: "foo", scope: .command),
            "bar"
        )
        XCTAssertEqual(
            DictionaryMatcher.apply(entries: [e], to: "foo", scope: .prose),
            "bar"
        )
    }

    func testDisabledEntryIsNoOp() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l", enabled: false)],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }

    func testMultiTokenSpoken() {
        let result = DictionaryMatcher.apply(
            entries: [entry("my email", "andy@kumeda.com", mode: .prose)],
            to: "send my email to him",
            scope: .prose
        )
        XCTAssertEqual(result, "send andy@kumeda.com to him")
    }

    func testEmptyReplacementDeletesTokens() {
        let result = DictionaryMatcher.apply(
            entries: [entry("um", "")],
            to: "ls um now",
            scope: .command
        )
        XCTAssertEqual(result, "ls now")
    }

    func testEmptyReplacementAtStart() {
        let result = DictionaryMatcher.apply(
            entries: [entry("um", "", startsWith: true)],
            to: "um ls now",
            scope: .command
        )
        XCTAssertEqual(result, "ls now")
    }

    func testEmptyReplacementAtEnd() {
        let result = DictionaryMatcher.apply(
            entries: [entry("now", "")],
            to: "ls now",
            scope: .command
        )
        XCTAssertEqual(result, "ls")
    }

    func testLongerSpokenWinsOverShorter() {
        // "double dash" (2 tokens) should win over "dash" (1 token) when both
        // could match overlapping windows.
        let entries = [
            entry("dash", "-", mode: .both),
            entry("double dash", "--", mode: .both),
        ]
        let result = DictionaryMatcher.apply(
            entries: entries,
            to: "ls double dash all",
            scope: .command
        )
        XCTAssertEqual(result, "ls -- all")
    }

    func testMultipleNonOverlappingMatchesInOnePass() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "ls -shell -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -l -l")
    }

    func testEmptyInputReturnsEmpty() {
        let result = DictionaryMatcher.apply(
            entries: [entry("foo", "bar")],
            to: "",
            scope: .command
        )
        XCTAssertEqual(result, "")
    }

    func testNoEntriesIsNoOp() {
        let result = DictionaryMatcher.apply(
            entries: [],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }
}
```

- [ ] **Step 2.2: Run tests to verify they all fail**

Run: `swift test --filter DictionaryMatcherTests 2>&1 | tail -20`
Expected: build error — `cannot find 'DictionaryMatcher' in scope`. (We have not implemented it yet.)

- [ ] **Step 2.3: Implement `DictionaryMatcher`**

Create `Sources/vox/Util/DictionaryMatcher.swift`:

```swift
import Foundation

public enum DictionaryMatcher {

    /// Apply all enabled entries (matching `scope`) to `input`, returning
    /// the rewritten string. Pure function — no I/O.
    public static func apply(
        entries: [DictionaryEntry],
        to input: String,
        scope: Scope
    ) -> String {
        guard !input.isEmpty else { return input }
        let active = entries.filter { e in
            e.enabled && (e.mode == scope || e.mode == .both)
        }
        guard !active.isEmpty else { return input }

        // Longer-spoken wins. Tokenize spoken once per entry for sort + match.
        let prepared: [(entry: DictionaryEntry, spokenTokens: [String])] =
            active.map { ($0, tokenize($0.spoken)) }
                .filter { !$0.1.isEmpty }
                .sorted { $0.1.count > $1.1.count }

        var tokens = tokenize(input)
        for (e, sp) in prepared {
            tokens = replace(in: tokens, spoken: sp, entry: e)
        }
        return tokens.joined(separator: " ")
    }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func tokensEqual(_ a: String, _ b: String, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            return a.compare(b, options: .caseInsensitive) == .orderedSame
        }
        return a == b
    }

    private static func replace(
        in input: [String],
        spoken: [String],
        entry: DictionaryEntry
    ) -> [String] {
        let n = input.count
        let k = spoken.count
        guard k > 0, k <= n else { return input }
        let replacement = tokenize(entry.replacement)

        func windowMatches(at i: Int) -> Bool {
            guard i + k <= n else { return false }
            for j in 0..<k {
                if !tokensEqual(input[i + j], spoken[j], caseInsensitive: entry.caseInsensitive) {
                    return false
                }
            }
            return true
        }

        if entry.startsWith {
            // Only one possible match site: index 0.
            if windowMatches(at: 0) {
                return replacement + Array(input[k...])
            }
            return input
        }

        var out: [String] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            if windowMatches(at: i) {
                out.append(contentsOf: replacement)
                i += k
            } else {
                out.append(input[i])
                i += 1
            }
        }
        return out
    }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

Run: `swift test --filter DictionaryMatcherTests 2>&1 | tail -10`
Expected: all 17 tests pass. `Executed 17 tests, with 0 failures`.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/vox/Util/DictionaryMatcher.swift Tests/voxTests/DictionaryMatcherTests.swift
git commit --no-gpg-sign -m "Add DictionaryMatcher: token-based literal substitution"
```

---

## Task 3: Bundled defaults

**Files:**
- Create: `Sources/vox/Util/DictionaryDefaults.swift`

Migrates the current `misfireReplacements` map to typed entries with stable ids.

- [ ] **Step 3.1: Write the file**

```swift
import Foundation

enum DictionaryDefaults {

    /// Built-in entries seeded on first launch. Each id is stable across
    /// versions; new app versions may append entries with new ids — never
    /// renumber existing ones.
    static let bundledDefaults: [DictionaryEntry] = [
        // Single-letter flag misfires: -<word> -> -l
        DictionaryEntry(id: "builtin-shell-l", spoken: "-shell", replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-shall-l", spoken: "-shall", replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-sell-l",  spoken: "-sell",  replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-cell-l",  spoken: "-cell",  replacement: "-l",
                        mode: .command, isBuiltIn: true),
        // Single-letter flag misfires: -<word> -> -a
        DictionaryEntry(id: "builtin-hey-a",   spoken: "-hey",   replacement: "-a",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hay-a",   spoken: "-hay",   replacement: "-a",
                        mode: .command, isBuiltIn: true),
        // Leading false-start before a dash flag -> "ls".
        DictionaryEntry(id: "builtin-hello-comma-ls", spoken: "hello,", replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hello-ls",       spoken: "hello",  replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hi-comma-ls",    spoken: "hi,",    replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hi-ls",          spoken: "hi",     replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hey-comma-ls",   spoken: "hey,",   replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hey-ls",         spoken: "hey",    replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
    ]
}
```

Note: the old regex `^(?:hello|hi|hey),?\\s+(?=-)` is expanded into 6 stand-alone token-literal entries (each surface form: with/without comma × hello/hi/hey). The old `\b-(shell|shall|sell|cell)\b` becomes 4 entries; `\b-(hey|hay)\b` becomes 2.

- [ ] **Step 3.2: Verify the package compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3.3: Commit**

```bash
git add Sources/vox/Util/DictionaryDefaults.swift
git commit --no-gpg-sign -m "Add bundledDefaults: 12 built-in dictionary entries"
```

---

## Task 4: `DictionaryStore` — load, seed-merge, save (no watcher yet)

**Files:**
- Create: `Sources/vox/Util/DictionaryStore.swift`
- Test: `Tests/voxTests/DictionaryStoreTests.swift`

Watcher is added in a later task to keep this one focused.

- [ ] **Step 4.1: Write the failing test file**

Create `Tests/voxTests/DictionaryStoreTests.swift`:

```swift
import XCTest
@testable import vox

final class DictionaryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-dict-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(defaults: [DictionaryEntry] = DictionaryDefaults.bundledDefaults)
        -> DictionaryStore
    {
        DictionaryStore(
            fileURL: tempDir.appendingPathComponent("dictionary.json"),
            bundledDefaults: defaults
        )
    }

    func testFirstLaunchSeedsAllBuiltins() throws {
        let store = makeStore()
        store.load()
        XCTAssertEqual(store.entries.count, DictionaryDefaults.bundledDefaults.count)
        XCTAssertTrue(store.entries.allSatisfy { $0.isBuiltIn })
        // File now exists on disk.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("dictionary.json").path))
    }

    func testUpgradeAddsMissingBuiltinIds() throws {
        // Pre-populate file with only one of two defaults.
        let url = tempDir.appendingPathComponent("dictionary.json")
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "entries": [
                ["id": "builtin-A", "spoken": "a", "replacement": "A",
                 "mode": "command", "startsWith": false, "caseInsensitive": true,
                 "enabled": true, "isBuiltIn": true]
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: url)

        let defaults = [
            DictionaryEntry(id: "builtin-A", spoken: "a", replacement: "A",
                            mode: .command, isBuiltIn: true),
            DictionaryEntry(id: "builtin-B", spoken: "b", replacement: "B",
                            mode: .command, isBuiltIn: true),
        ]
        let store = makeStore(defaults: defaults)
        store.load()
        XCTAssertEqual(store.entries.map(\.id).sorted(), ["builtin-A", "builtin-B"])
    }

    func testUpgradePreservesUserEditOfBuiltin() throws {
        let url = tempDir.appendingPathComponent("dictionary.json")
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "entries": [
                ["id": "builtin-A", "spoken": "a", "replacement": "EDITED",
                 "mode": "command", "startsWith": false, "caseInsensitive": true,
                 "enabled": true, "isBuiltIn": true]
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: url)

        let defaults = [
            DictionaryEntry(id: "builtin-A", spoken: "a", replacement: "ORIGINAL",
                            mode: .command, isBuiltIn: true),
        ]
        let store = makeStore(defaults: defaults)
        store.load()
        XCTAssertEqual(store.entries.first?.replacement, "EDITED")
    }

    func testDisabledBuiltinStaysDisabledAcrossReload() throws {
        let store = makeStore()
        store.load()
        var firstId = store.entries[0].id
        store.setEnabled(id: firstId, enabled: false)
        // New store reading same file.
        let store2 = makeStore()
        store2.load()
        let entry = store2.entries.first(where: { $0.id == firstId })
        XCTAssertEqual(entry?.enabled, false)
        _ = firstId  // silence unused mutation warning if any
    }

    func testUserEntrySurvivesReload() throws {
        let store = makeStore()
        store.load()
        let user = DictionaryEntry(id: "user-test-1", spoken: "vox", replacement: "Vox",
                                   mode: .prose, isBuiltIn: false)
        store.add(user)
        let store2 = makeStore()
        store2.load()
        XCTAssertNotNil(store2.entries.first(where: { $0.id == "user-test-1" }))
    }

    func testMalformedJsonFallsBackAndFlagsError() throws {
        let url = tempDir.appendingPathComponent("dictionary.json")
        try Data("{ not valid json".utf8).write(to: url)
        let store = makeStore()
        store.load()
        // Falls back to bundled defaults in memory; loadError is set.
        XCTAssertEqual(store.entries.count, DictionaryDefaults.bundledDefaults.count)
        XCTAssertNotNil(store.loadError)
    }

    func testDuplicateIdFirstWins() throws {
        let url = tempDir.appendingPathComponent("dictionary.json")
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "entries": [
                ["id": "user-x", "spoken": "a", "replacement": "FIRST",
                 "mode": "command", "startsWith": false, "caseInsensitive": true,
                 "enabled": true, "isBuiltIn": false],
                ["id": "user-x", "spoken": "a", "replacement": "SECOND",
                 "mode": "command", "startsWith": false, "caseInsensitive": true,
                 "enabled": true, "isBuiltIn": false],
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: url)
        let store = makeStore(defaults: [])
        store.load()
        XCTAssertEqual(store.entries.filter { $0.id == "user-x" }.count, 1)
        XCTAssertEqual(store.entries.first(where: { $0.id == "user-x" })?.replacement, "FIRST")
    }

    func testAtomicWriteRoundTrips() throws {
        let store = makeStore()
        store.load()
        let user = DictionaryEntry(id: "user-rt", spoken: "x", replacement: "y",
                                   mode: .both, isBuiltIn: false)
        store.add(user)
        // Re-read raw file and decode.
        let url = tempDir.appendingPathComponent("dictionary.json")
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DictionaryFileV1.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.entries.contains(where: { $0.id == "user-rt" }))
    }

    func testDeleteUserEntryRemovesIt() throws {
        let store = makeStore()
        store.load()
        let user = DictionaryEntry(id: "user-del", spoken: "x", replacement: "y",
                                   mode: .both, isBuiltIn: false)
        store.add(user)
        store.delete(id: "user-del")
        XCTAssertNil(store.entries.first(where: { $0.id == "user-del" }))
    }

    func testDeleteBuiltinReappearsOnReload() throws {
        let store = makeStore()
        store.load()
        let firstBuiltinId = store.entries[0].id
        store.delete(id: firstBuiltinId)
        XCTAssertNil(store.entries.first(where: { $0.id == firstBuiltinId }))
        // Reload — seed-merge re-adds.
        let store2 = makeStore()
        store2.load()
        XCTAssertNotNil(store2.entries.first(where: { $0.id == firstBuiltinId }))
    }
}
```

- [ ] **Step 4.2: Run tests to verify they fail**

Run: `swift test --filter DictionaryStoreTests 2>&1 | tail -10`
Expected: build error — `cannot find 'DictionaryStore' in scope` and `'DictionaryFileV1'`.

- [ ] **Step 4.3: Implement `DictionaryStore`**

Create `Sources/vox/Util/DictionaryStore.swift`:

```swift
import Foundation
import Combine

/// On-disk envelope for the dictionary file.
public struct DictionaryFileV1: Codable {
    public var schemaVersion: Int
    public var entries: [DictionaryEntry]
}

public final class DictionaryStore: ObservableObject {

    public static let shared: DictionaryStore = DictionaryStore(
        fileURL: DictionaryStore.defaultFileURL(),
        bundledDefaults: DictionaryDefaults.bundledDefaults
    )

    @Published public private(set) var entries: [DictionaryEntry] = []
    @Published public private(set) var loadError: String?

    public let fileURL: URL
    private let bundledDefaults: [DictionaryEntry]

    public init(fileURL: URL, bundledDefaults: [DictionaryEntry]) {
        self.fileURL = fileURL
        self.bundledDefaults = bundledDefaults
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Vox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dictionary.json")
    }

    /// Load from disk, seed-merge defaults, write back if mutated.
    public func load() {
        let onDisk = readFile()
        var merged = onDisk.entries

        let presentBuiltinIds = Set(merged.filter(\.isBuiltIn).map(\.id))
        var didMutate = false
        for d in bundledDefaults where !presentBuiltinIds.contains(d.id) {
            merged.append(d)
            didMutate = true
        }

        // Drop duplicate ids — first wins.
        var seen = Set<String>()
        let deduped = merged.filter { e in
            if seen.contains(e.id) { return false }
            seen.insert(e.id)
            return true
        }
        if deduped.count != merged.count {
            merged = deduped
            didMutate = true
        }

        self.entries = merged
        if didMutate {
            try? write(entries: merged)
        }
    }

    public func add(_ entry: DictionaryEntry) {
        entries.append(entry)
        try? write(entries: entries)
    }

    public func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        try? write(entries: entries)
    }

    public func delete(id: String) {
        entries.removeAll { $0.id == id }
        try? write(entries: entries)
    }

    public func setEnabled(id: String, enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].enabled = enabled
        try? write(entries: entries)
    }

    // MARK: - File I/O

    private func readFile() -> DictionaryFileV1 {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadError = nil
            return DictionaryFileV1(schemaVersion: 1, entries: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(DictionaryFileV1.self, from: data)
            if decoded.schemaVersion != 1 {
                loadError = "Unsupported schemaVersion \(decoded.schemaVersion); using defaults."
                return DictionaryFileV1(schemaVersion: 1, entries: bundledDefaults)
            }
            loadError = nil
            return decoded
        } catch {
            loadError = "Could not parse dictionary.json: \(error.localizedDescription)"
            return DictionaryFileV1(schemaVersion: 1, entries: bundledDefaults)
        }
    }

    private func write(entries: [DictionaryEntry]) throws {
        let envelope = DictionaryFileV1(schemaVersion: 1, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        // Replace destination atomically.
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }
}
```

- [ ] **Step 4.4: Run tests to verify they pass**

Run: `swift test --filter DictionaryStoreTests 2>&1 | tail -20`
Expected: all 10 tests pass.

If `testMalformedJsonFallsBackAndFlagsError` fails because `entries.count` doesn't equal `bundledDefaults.count`: confirm `readFile()` returns `bundledDefaults` on malformed and that `load()` then merges them in.

- [ ] **Step 4.5: Commit**

```bash
git add Sources/vox/Util/DictionaryStore.swift Tests/voxTests/DictionaryStoreTests.swift
git commit --no-gpg-sign -m "Add DictionaryStore: load, seed-merge, atomic save"
```

---

## Task 5: Wire `PostProcessor` to the dictionary; remove static misfire map

**Files:**
- Modify: `Sources/vox/Text/PostProcessor.swift`
- Modify: `Tests/voxTests/PostProcessorTests.swift`

The current static map and existing misfire tests get rewritten to flow through the dictionary path. Tests inject an explicit provider so they remain hermetic.

- [ ] **Step 5.1: Modify `PostProcessor` initializer + apply step**

Open `Sources/vox/Text/PostProcessor.swift`. Replace lines 1-13 (the `import` line through the existing `init`) with:

```swift
import Foundation

public struct PostProcessor {
    public let mode: TranscriptionMode
    private let numberNormalizer = NumberNormalizer()
    private let dictionaryProvider: () -> [DictionaryEntry]

    public init(
        mode: TranscriptionMode,
        dictionaryProvider: @escaping () -> [DictionaryEntry] = { DictionaryStore.shared.entries }
    ) {
        self.mode = mode
        self.dictionaryProvider = dictionaryProvider
    }
```

- [ ] **Step 5.2: Replace `fixCommonMisfires` call sites and add prose call**

In the same file, find the command-mode branch (around line 40-55) and the prose branch (around line 32-39). Replace the `switch mode` block with:

```swift
        switch mode {
        case .prose:
            s = capitalizeSentenceStarts(s)
            s = ensureTrailingTerminator(s)
            s = applyDictionary(.prose, s)
            // Send a Space keystroke after paste instead of appending " " to
            // the text. Some apps (notably Wave terminal) strip trailing
            // whitespace from pasted content; a discrete keystroke can't be
            // stripped that way.
            suffixKeys = [.space]
        case .command:
            s = lowercaseFirstLetter(s)
            s = stripTrailingSentencePunctuation(s)
            s = expandSpokenPunctuation(s)
            s = splitCommandFromFlag(s)
            s = applyDictionary(.command, s)
            let extracted = extractTrailingSuffixKeys(s)
            s = extracted.text
            suffixKeys = extracted.keys
            // If no other keys were extracted and we did paste something, send
            // a Space keystroke so back-to-back command-mode dictations are
            // separated. Skipped when tab/return/escape/control was already
            // attached (those have specific semantics that shouldn't get an
            // extra space prefix).
            if suffixKeys.isEmpty && !s.isEmpty {
                suffixKeys = [.space]
            }
        }
```

- [ ] **Step 5.3: Add `applyDictionary` helper; delete `fixCommonMisfires` and `misfireReplacements`**

In the same file, find the `// MARK: - Common misfire fixups (command mode)` section and DELETE it entirely (the `misfireReplacements` static array and the `fixCommonMisfires` function — about 25 lines).

Add this new helper directly above the `// MARK: - Spoken punctuation (command mode)` mark:

```swift
    // MARK: - User dictionary

    private func applyDictionary(_ scope: Scope, _ input: String) -> String {
        DictionaryMatcher.apply(entries: dictionaryProvider(), to: input, scope: scope)
    }
```

- [ ] **Step 5.4: Update existing tests to inject an empty dictionary provider where needed**

Open `Tests/voxTests/PostProcessorTests.swift`. The existing `testCommandFixes*` tests rely on the now-deleted static map. Replace them with the same names but driven by an explicit injection of `DictionaryDefaults.bundledDefaults`.

Find the section `// MARK: - Common misfire fixups`. Replace its contents with:

```swift
    // MARK: - Common misfire fixups (now driven by built-in dictionary defaults)

    private func dictPostProcessor(_ mode: TranscriptionMode) -> PostProcessor {
        PostProcessor(
            mode: mode,
            dictionaryProvider: { DictionaryDefaults.bundledDefaults }
        )
    }

    func testCommandFixesShellMisfireAsLowercaseL() {
        XCTAssertEqual(dictPostProcessor(.command).apply("ls -shell"), "ls -l")
    }

    func testCommandFixesShallMisfireAsLowercaseL() {
        XCTAssertEqual(dictPostProcessor(.command).apply("ls -shall"), "ls -l")
    }

    func testCommandFixesLeadingHelloBeforeDashAsLs() {
        XCTAssertEqual(dictPostProcessor(.command).apply("hello, -shell"), "ls -l")
    }

    func testCommandFixesLeadingHiBeforeDashAsLs() {
        XCTAssertEqual(dictPostProcessor(.command).apply("hi -a"), "ls -a")
    }

    func testCommandFixesHeyMisfireAsLowercaseA() {
        XCTAssertEqual(dictPostProcessor(.command).apply("ls -hey"), "ls -a")
    }

    func testCommandLeavesLongFlagShellAlone() {
        // "--shell" is a single token; "-shell" entry must not match inside it.
        XCTAssertEqual(
            dictPostProcessor(.command).apply("usermod --shell /bin/zsh"),
            "usermod --shell /bin/zsh"
        )
    }

    func testCommandLeavesShellWordWithoutDashAlone() {
        XCTAssertEqual(dictPostProcessor(.command).apply("which shell"), "which shell")
    }
```

For the tests OUTSIDE that section that still use plain `PostProcessor(mode: .command)` or `PostProcessor(mode: .prose)` — those default to `DictionaryStore.shared.entries`, which reads the real on-disk file. To keep tests hermetic, we will NOT change them in this task; the global `DictionaryStore.shared` is initialized lazily and its load() is called on app start, not on `entries` access — so during tests it returns an empty list. Verify in the next step.

- [ ] **Step 5.5: Run all PostProcessor tests**

Run: `swift test --filter PostProcessorTests 2>&1 | tail -15`
Expected: all PostProcessorTests pass.

If any prose test fails because `DictionaryStore.shared` returned defaults, change those tests to also use `dictPostProcessor(.prose)` with an empty provider:

```swift
    private func bareProse() -> PostProcessor {
        PostProcessor(mode: .prose, dictionaryProvider: { [] })
    }
```
and update affected tests to use `bareProse().apply(...)`.

- [ ] **Step 5.6: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 5.7: Commit**

```bash
git add Sources/vox/Text/PostProcessor.swift Tests/voxTests/PostProcessorTests.swift
git commit --no-gpg-sign -m "PostProcessor: drive misfire fixups via DictionaryStore"
```

---

## Task 6: New PostProcessor tests — prose mode + scope filter

**Files:**
- Modify: `Tests/voxTests/PostProcessorTests.swift`

Coverage for behavior the spec requires but the migrated misfire tests don't exercise.

- [ ] **Step 6.1: Append new tests at the end of the test class**

Open `Tests/voxTests/PostProcessorTests.swift`. Just before the closing `}` of the class, append:

```swift
    // MARK: - Dictionary scope behavior

    func testProseDictionaryReplacesMidSentenceProperNoun() {
        let entries = [DictionaryEntry(
            id: "user-vox-cap", spoken: "vox", replacement: "Vox", mode: .prose,
            isBuiltIn: false
        )]
        let p = PostProcessor(mode: .prose, dictionaryProvider: { entries })
        XCTAssertEqual(p.apply("running vox today"), "Running Vox today.")
    }

    func testProseDictionaryDoesNotFireInCommandMode() {
        let entries = [DictionaryEntry(
            id: "user-vox-cap", spoken: "vox", replacement: "Vox", mode: .prose,
            isBuiltIn: false
        )]
        let p = PostProcessor(mode: .command, dictionaryProvider: { entries })
        XCTAssertEqual(p.apply("vox status"), "vox status")
    }

    func testCommandDictionaryDoesNotFireInProseMode() {
        let entries = [DictionaryEntry(
            id: "user-foo", spoken: "foo", replacement: "bar", mode: .command,
            isBuiltIn: false
        )]
        let p = PostProcessor(mode: .prose, dictionaryProvider: { entries })
        XCTAssertEqual(p.apply("foo is here"), "Foo is here.")
    }

    func testBothScopeFiresInBothModes() {
        let entries = [DictionaryEntry(
            id: "user-foo", spoken: "foo", replacement: "bar", mode: .both,
            isBuiltIn: false
        )]
        XCTAssertEqual(
            PostProcessor(mode: .prose, dictionaryProvider: { entries }).apply("foo"),
            "Bar."
        )
        XCTAssertEqual(
            PostProcessor(mode: .command, dictionaryProvider: { entries }).apply("foo"),
            "bar"
        )
    }

    func testDisabledEntryIsNoOpInPipeline() {
        let entries = [DictionaryEntry(
            id: "user-foo", spoken: "foo", replacement: "bar",
            mode: .command, enabled: false, isBuiltIn: false
        )]
        let p = PostProcessor(mode: .command, dictionaryProvider: { entries })
        XCTAssertEqual(p.apply("foo"), "foo")
    }

    func testEmptyReplacementDeletesTokenInPipeline() {
        let entries = [DictionaryEntry(
            id: "user-um", spoken: "um", replacement: "", mode: .command,
            isBuiltIn: false
        )]
        let p = PostProcessor(mode: .command, dictionaryProvider: { entries })
        XCTAssertEqual(p.apply("ls um now"), "ls now")
    }
```

- [ ] **Step 6.2: Run tests**

Run: `swift test --filter PostProcessorTests 2>&1 | tail -10`
Expected: all pass, including 6 new tests.

- [ ] **Step 6.3: Commit**

```bash
git add Tests/voxTests/PostProcessorTests.swift
git commit --no-gpg-sign -m "PostProcessor: tests for dictionary scope, both, disabled, empty replacement"
```

---

## Task 7: File watcher

**Files:**
- Modify: `Sources/vox/Util/DictionaryStore.swift`

Adds `DispatchSource` watching with debounce + reload-on-app-focus fallback. Watcher is non-blocking and lazy — `start()` is called explicitly by `AppDelegate` (Task 9). Keeping it out of the singleton's init keeps unit tests hermetic.

- [ ] **Step 7.1: Add watcher fields and methods to `DictionaryStore`**

In `Sources/vox/Util/DictionaryStore.swift`, add the following inside the `DictionaryStore` class (after `loadError` declaration):

```swift
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchFD: Int32 = -1
    private var debounceTimer: DispatchSourceTimer?
    private let watchQueue = DispatchQueue(label: "vox.dictionary.watch")

    /// Start watching the file. Idempotent.
    public func startWatching() {
        stopWatching()
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: watchQueue
        )
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { [weak self] in
            if let self = self, self.watchFD >= 0 {
                close(self.watchFD)
                self.watchFD = -1
            }
        }
        watchFD = fd
        watchSource = src
        src.resume()
    }

    public func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    private func scheduleReload() {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: watchQueue)
        timer.schedule(deadline: .now() + .milliseconds(250))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.load()
                // File descriptor is invalidated by atomic rename; rebind.
                self?.startWatching()
            }
        }
        timer.resume()
        debounceTimer = timer
    }
```

- [ ] **Step 7.2: Verify the package compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7.3: Run all existing tests to verify no regression**

Run: `swift test 2>&1 | tail -10`
Expected: all pass.

(No new tests for the watcher itself — `DispatchSource` is hard to drive deterministically in XCTest. We rely on integration testing in Task 10.)

- [ ] **Step 7.4: Commit**

```bash
git add Sources/vox/Util/DictionaryStore.swift
git commit --no-gpg-sign -m "DictionaryStore: file watcher with 250ms debounce + rebind"
```

---

## Task 8: Settings UI — Dictionary section

**Files:**
- Modify: `Sources/vox/App/SettingsWindow.swift`

Adds a new SwiftUI section after the Usage panel: list of entries with toggle/edit/delete, an Add button, and a Reveal-in-Finder button.

- [ ] **Step 8.1: Read current `SettingsView` end**

Run: `swift build` to confirm clean baseline. Open `Sources/vox/App/SettingsWindow.swift` and identify where the Usage section ends (just before the closing `}` of `body`).

- [ ] **Step 8.2: Add `@StateObject` binding and Dictionary section**

Near the existing `@State` declarations at the top of `SettingsView`, add:

```swift
    @StateObject private var dict = DictionaryStore.shared
    @State private var editingEntry: DictionaryEntry?
    @State private var isAddingEntry: Bool = false
```

After the Usage panel's closing brace (just before the outer VStack closes), add a new `Divider()` followed by:

```swift
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Dictionary")
                        .font(.headline)
                    Spacer()
                    Button {
                        editingEntry = DictionaryEntry(
                            id: "user-\(UUID().uuidString)",
                            spoken: "", replacement: "",
                            mode: .command, isBuiltIn: false
                        )
                        isAddingEntry = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([dict.fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }

                if let err = dict.loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                List {
                    ForEach(dict.entries) { entry in
                        DictionaryRow(
                            entry: entry,
                            onToggle: { dict.setEnabled(id: entry.id, enabled: !entry.enabled) },
                            onEdit: { editingEntry = entry; isAddingEntry = false },
                            onDelete: { dict.delete(id: entry.id) }
                        )
                    }
                }
                .frame(minHeight: 180, maxHeight: 360)

                Text("\(dict.entries.count) entries · \(dict.entries.filter { !$0.enabled }.count) disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(item: $editingEntry) { entry in
                DictionaryEditSheet(
                    entry: entry,
                    isNew: isAddingEntry,
                    onSave: { saved in
                        if isAddingEntry { dict.add(saved) } else { dict.update(saved) }
                        editingEntry = nil
                    },
                    onCancel: { editingEntry = nil }
                )
            }
```

- [ ] **Step 8.3: Add `DictionaryRow` and `DictionaryEditSheet` views**

At the bottom of `SettingsWindow.swift` (after the existing `SettingsView` struct), add:

```swift
struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: .init(get: { entry.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.spoken).font(.system(.body, design: .monospaced))
                    Text("→").foregroundStyle(.secondary)
                    Text(entry.replacement.isEmpty ? "(delete)" : entry.replacement)
                        .font(.system(.body, design: .monospaced))
                }
                HStack(spacing: 8) {
                    Text(entry.mode.rawValue).font(.caption).foregroundStyle(.secondary)
                    if entry.startsWith {
                        Text("start").font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.isBuiltIn {
                        Text("built-in").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            if !entry.isBuiltIn {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DictionaryEditSheet: View {
    @State var entry: DictionaryEntry
    let isNew: Bool
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add entry" : "Edit entry").font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spoken").font(.caption)
                TextField("e.g. vox", text: $entry.spoken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Replacement").font(.caption)
                TextField("e.g. Vox", text: $entry.replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                Picker("Mode", selection: $entry.mode) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .frame(maxWidth: 180)

                Toggle("Match only at start", isOn: $entry.startsWith)
                Toggle("Case-insensitive", isOn: $entry.caseInsensitive)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") { onSave(entry) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.spoken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
```

- [ ] **Step 8.4: Verify the package compiles**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. SwiftUI iterates `.sheet(item:)` so `DictionaryEntry` must conform to `Identifiable` (already does via `id: String`).

If there are type-inference errors around `Toggle` initializers, simplify to:

```swift
Toggle("", isOn: Binding(
    get: { entry.enabled },
    set: { _ in onToggle() }
))
.labelsHidden()
```

- [ ] **Step 8.5: Run the full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 8.6: Commit**

```bash
git add Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "Settings UI: Dictionary section with add/edit/delete + Reveal in Finder"
```

---

## Task 9: Hook `DictionaryStore` lifecycle in AppDelegate

**Files:**
- Modify: `Sources/vox/App/AppDelegate.swift`

Calls `load()` then `startWatching()` on app launch; falls back to reload-on-focus if the watcher fails.

- [ ] **Step 9.1: Read AppDelegate to find the launch hook**

Run: `grep -n "applicationDidFinishLaunching\|applicationDidBecomeActive" Sources/vox/App/AppDelegate.swift`

Identify the `applicationDidFinishLaunching(_:)` method.

- [ ] **Step 9.2: Add startup call**

In `applicationDidFinishLaunching(_:)`, append (before any return):

```swift
        DictionaryStore.shared.load()
        DictionaryStore.shared.startWatching()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Cheap belt-and-suspenders: reload on focus in case the watcher
            // missed an event or never started.
            DictionaryStore.shared.load()
        }
```

- [ ] **Step 9.3: Verify the package compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 9.4: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 9.5: Commit**

```bash
git add Sources/vox/App/AppDelegate.swift
git commit --no-gpg-sign -m "AppDelegate: load + watch DictionaryStore on launch"
```

---

## Task 10: Manual integration smoke test

No code changes — verifies the whole feature end-to-end on a real macOS run.

- [ ] **Step 10.1: Build and launch the app**

Run: `swift build -c release && open .build/release/vox` (or whatever the existing run script does — check `setup.sh` if unsure).

- [ ] **Step 10.2: First-launch seed**

- Open Settings → Dictionary section. Confirm 12 built-in entries listed.
- Confirm `~/Library/Application Support/Vox/dictionary.json` exists with `schemaVersion: 1` and 12 entries.

- [ ] **Step 10.3: In-app edit**

- Click Add. Fill: spoken=`vox`, replacement=`Vox`, mode=`prose`.
- Save. Dictate "I love vox" in prose mode. Verify the pasted text reads "I love Vox."

- [ ] **Step 10.4: External edit + watcher**

- With the app running, open the JSON file in an editor.
- Change one user entry's `replacement`, save.
- Within ~1s the Settings table should update without a relaunch.
- Dictate the affected phrase; verify the new replacement is used.

- [ ] **Step 10.5: Disable a built-in**

- Toggle off `builtin-shell-l` in Settings.
- Dictate `ls -shell`. Verify output is `ls -shell` (no longer rewritten to `ls -l`).

- [ ] **Step 10.6: Delete the JSON file**

- Quit Vox.
- `rm ~/Library/Application\ Support/Vox/dictionary.json`
- Relaunch Vox. Confirm the file is recreated with all 12 built-ins.

- [ ] **Step 10.7: Malformed JSON**

- Quit Vox. Edit the file, corrupt it (e.g., add a stray `{` at the top).
- Relaunch. Confirm Settings shows the load-error banner and the in-memory list still has the bundled defaults.

If all 7 manual checks pass, the feature is complete. Open a PR or merge to main per project conventions.

---

## Self-review checklist (pre-handoff)

- [x] Spec coverage: every section of `2026-04-27-user-dictionary-design.md` has a corresponding task (schema → Task 1; matcher → Task 2; defaults → Task 3; load/seed/save → Task 4; pipeline integration → Task 5/6; watcher → Task 7; UI → Task 8; lifecycle → Task 9; integration → Task 10).
- [x] No placeholders ("TBD", "TODO", "implement appropriate validation") — all steps contain concrete code or commands.
- [x] Type names consistent across tasks: `DictionaryEntry`, `Scope`, `DictionaryMatcher.apply`, `DictionaryStore`, `DictionaryFileV1`, `DictionaryDefaults.bundledDefaults` referenced uniformly.
- [x] All file paths are absolute-from-repo-root and exist or are explicitly created.
- [x] Each TDD task writes the failing test before the implementation.
- [x] Commits land at task boundaries; no oversized changes.
