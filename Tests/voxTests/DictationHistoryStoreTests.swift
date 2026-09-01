import XCTest
@testable import vox

final class DictationHistoryStoreTests: XCTestCase {
    private let encryptionKey = Data(repeating: 0xA5, count: 32)
    private var tempDirectory: URL!
    private var historyURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-dictation-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        historyURL = tempDirectory.appendingPathComponent("history.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testRecordPreservesMalformedHistory() throws {
        let malformed = Data("{ definitely not valid history".utf8)
        try malformed.write(to: historyURL)
        let messages = LockedMessages()
        let decoder = CountingHistoryDecoder()
        let store = DictationHistoryStore(
            fileURL: historyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { messages.append($0) }
        )

        store.record(makeEntry(text: "Must not replace the damaged file"))

        XCTAssertEqual(store.list(), [])
        XCTAssertFalse(store.record(makeEntry(text: "Still blocked")))
        XCTAssertEqual(try Data(contentsOf: historyURL), malformed)
        XCTAssertEqual(decoder.decodeCount, 1)
        XCTAssertTrue(messages.values.contains { $0.contains("decode failed") })
    }

    func testRecordPreservesUnreadableHistory() throws {
        try writeEntries([])
        let original = try Data(contentsOf: historyURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: historyURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: historyURL.path
            )
        }
        let messages = LockedMessages()
        let store = DictationHistoryStore(
            fileURL: historyURL,
            decoder: CountingHistoryDecoder(),
            keyProvider: { self.encryptionKey },
            log: { messages.append($0) }
        )
        let noChange = expectation(description: "unreadable history is not replaced")
        noChange.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { _ in noChange.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.record(makeEntry(text: "Must preserve unreadable history"))
        _ = store.list()

        wait(for: [noChange], timeout: 0.1)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: historyURL.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0)
        XCTAssertTrue(messages.values.contains { $0.contains("read failed") })

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: historyURL.path
        )
        XCTAssertEqual(try Data(contentsOf: historyURL), original)
    }

    func testMissingHistoryIsValidEmptyAndRecordsSuccessfully() {
        let store = makeStore()
        let changed = expectation(description: "successful write posts a change")
        let observer = NotificationCenter.default.addObserver(
            forName: .dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { _ in
            changed.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(store.list(), [])
        XCTAssertNil(store.last())

        let entry = makeEntry(text: "First persisted entry")
        store.record(entry)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(store.list(), [entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))
        let persisted = try? Data(contentsOf: historyURL)
        XCTAssertTrue(persisted.map(TranscriptCipher.isEncryptedEnvelope) == true)
        XCTAssertFalse(String(data: persisted ?? Data(), encoding: .utf8)?.contains(entry.text) == true)
    }

    func testLegacyPlaintextMigratesAndIsRemovedAfterVerification() throws {
        let legacyURL = tempDirectory.appendingPathComponent("history.json")
        let encryptedURL = tempDirectory.appendingPathComponent("history.enc")
        let entry = makeEntry(text: "Legacy private text")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([entry]).write(to: legacyURL, options: .atomic)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = DictationHistoryStore(
            fileURL: encryptedURL,
            legacyURL: legacyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { _ in }
        )

        XCTAssertEqual(store.list(), [entry])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(TranscriptCipher.isEncryptedEnvelope(try Data(contentsOf: encryptedURL)))
    }

    func testVerifiedEncryptedHistoryRetriesLegacyPlaintextRemoval() throws {
        let legacyURL = tempDirectory.appendingPathComponent("history.json")
        let encryptedURL = tempDirectory.appendingPathComponent("history.enc")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let initial = DictationHistoryStore(
            fileURL: encryptedURL,
            legacyURL: legacyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { _ in }
        )
        let entry = makeEntry(text: "Encrypted source of truth")
        XCTAssertTrue(initial.record(entry))

        try Data("leftover plaintext".utf8).write(to: legacyURL)
        let reloaded = DictationHistoryStore(
            fileURL: encryptedURL,
            legacyURL: legacyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { _ in }
        )

        XCTAssertEqual(reloaded.list(), [entry])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testUnavailableKeyPreventsWriteWithoutCreatingPlaintext() {
        struct KeyUnavailable: Error {}
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = DictationHistoryStore(
            fileURL: historyURL,
            decoder: decoder,
            keyProvider: { throw KeyUnavailable() },
            log: { _ in }
        )

        XCTAssertFalse(store.record(makeEntry(text: "Must remain in memory only")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testUnchangedHistoryIsDecodedOnlyOnceAcrossReadsAndRecord() throws {
        let existing = makeEntry(text: "Existing entry")
        try writeEntries([existing])
        let decoder = CountingHistoryDecoder()
        let store = DictationHistoryStore(
            fileURL: historyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { _ in }
        )

        XCTAssertEqual(store.list(), [existing])
        let decodeCountAfterMigration = decoder.decodeCount
        XCTAssertEqual(store.last(), existing)
        XCTAssertEqual(decoder.decodeCount, decodeCountAfterMigration)

        let appended = makeEntry(text: "Appended entry")
        let changed = expectation(description: "record completes")
        let observer = NotificationCenter.default.addObserver(
            forName: .dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { _ in changed.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.record(appended)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(store.list(), [existing, appended])
        XCTAssertEqual(decoder.decodeCount, decodeCountAfterMigration + 1)
    }

    func testFailedWriteLogsErrorWithoutPostingChangeNotification() throws {
        let parentFile = tempDirectory.appendingPathComponent("not-a-directory")
        try Data("blocking file".utf8).write(to: parentFile)
        let unwritableHistoryURL = parentFile.appendingPathComponent("history.json")
        let messages = LockedMessages()
        let decoder = CountingHistoryDecoder()
        let store = DictationHistoryStore(
            fileURL: unwritableHistoryURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { messages.append($0) }
        )
        let noChange = expectation(description: "failed write does not post a change")
        noChange.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let sourceStore = notification.object as? DictationHistoryStore
            if notification.object == nil || sourceStore === store {
                noChange.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.record(makeEntry(text: "Cannot be persisted"))
        _ = store.list()

        wait(for: [noChange], timeout: 0.1)
        XCTAssertTrue(messages.values.contains { $0.contains("write failed") })
    }

    private func makeEntry(text: String) -> DictationEntry {
        DictationEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: "prose",
            durationSec: 1.5,
            wordCount: text.split(separator: " ").count,
            text: text
        )
    }

    private func makeStore() -> DictationHistoryStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return DictationHistoryStore(
            fileURL: historyURL,
            decoder: decoder,
            keyProvider: { self.encryptionKey },
            log: { _ in }
        )
    }

    private func writeEntries(_ entries: [DictationEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: historyURL, options: .atomic)
    }
}

private final class CountingHistoryDecoder: JSONDecoder, @unchecked Sendable {
    private(set) var decodeCount = 0

    override init() {
        super.init()
        dateDecodingStrategy = .iso8601
    }

    override func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        decodeCount += 1
        return try super.decode(type, from: data)
    }
}

private final class LockedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}
