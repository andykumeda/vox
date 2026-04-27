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
