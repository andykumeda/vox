import XCTest
@testable import vox

final class MeetingAudioArchiveTests: XCTestCase {
    private var directory: URL!
    private let key = Data(repeating: 0x4A, count: 32)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testMultiBlockArchiveVerifiesAndPreservesSourceWithPrivatePermissions() throws {
        let source = directory.appendingPathComponent("audio.m4a")
        let destination = directory.appendingPathComponent("audio.enc")
        let original = Data(repeating: 0xA5, count: 2_100_001)
        try original.write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: destination, key: key)
        try MeetingAudioArchive.verify(archive: destination, key: key)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let archive = try Data(contentsOf: destination)
        XCTAssertNotEqual(archive, original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertThrowsError(try MeetingAudioArchive.verify(archive: destination, key: Data(repeating: 0, count: 32)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["audio.enc", "audio.m4a"])
    }

    func testEmptyArchiveVerifies() throws {
        let source = directory.appendingPathComponent("audio.m4a")
        let destination = directory.appendingPathComponent("audio.enc")
        try Data().write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: destination, key: key)
        try MeetingAudioArchive.verify(archive: destination, key: key)
    }

    func testReplacementAndCrossArchiveBlockSplicing() throws {
        let source = directory.appendingPathComponent("audio.m4a")
        let destination = directory.appendingPathComponent("audio.enc")
        try Data(repeating: 0xA5, count: 128).write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: destination, key: key)
        let first = try Data(contentsOf: destination)
        try MeetingAudioArchive.encrypt(source: source, destination: destination, key: key)
        try MeetingAudioArchive.verify(archive: destination, key: key)
        let second = try Data(contentsOf: destination)
        XCTAssertNotEqual(first, second)
        let headerEnd = 8 + Int(first.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        try (first.prefix(headerEnd) + second.suffix(from: headerEnd)).write(to: destination)
        XCTAssertThrowsError(try MeetingAudioArchive.verify(archive: destination, key: key))
    }

    func testTamperingTruncationTrailingBytesAndBlockReorderingFail() throws {
        let source = directory.appendingPathComponent("audio.m4a")
        let destination = directory.appendingPathComponent("audio.enc")
        try Data(repeating: 0xA5, count: 2_100_001).write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: destination, key: key)
        let original = try Data(contentsOf: destination)
        var tampered = original
        tampered[tampered.count - 1] ^= 1
        let headerEnd = 8 + Int(original.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        let firstBlockEnd = headerEnd + 8 + Int(original[headerEnd..<(headerEnd + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        let secondBlockEnd = firstBlockEnd + 8 + Int(original[firstBlockEnd..<(firstBlockEnd + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        let reordered = original.prefix(headerEnd) + original[firstBlockEnd..<secondBlockEnd] + original[headerEnd..<firstBlockEnd] + original.suffix(from: secondBlockEnd)
        for invalid in [tampered, Data(original.dropLast()), Data(original.prefix(headerEnd)), original + Data([0]), reordered] {
            try invalid.write(to: destination)
            XCTAssertThrowsError(try MeetingAudioArchive.verify(archive: destination, key: key))
        }
    }

    func testDecryptsAuthenticatedMultiBlockArchiveWithPrivatePermissions() throws {
        let source = directory.appendingPathComponent("original.m4a")
        let archive = directory.appendingPathComponent("audio.enc")
        let destination = directory.appendingPathComponent("recovered.m4a")
        let original = Data(repeating: 0xA5, count: 2_100_001)
        try original.write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
        try Data("older contents".utf8).write(to: destination)
        try MeetingAudioArchive.decrypt(archive: archive, destination: destination, key: key)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int, 0o600)
    }

    func testFailedDecryptionPreservesDestinationAndRemovesPlaintextCandidate() throws {
        let source = directory.appendingPathComponent("original.m4a")
        let archive = directory.appendingPathComponent("audio.enc")
        let destination = directory.appendingPathComponent("recovered.m4a")
        try Data(repeating: 0xA5, count: 1_200_000).write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
        let prior = Data("existing destination".utf8)
        try prior.write(to: destination)
        XCTAssertThrowsError(try MeetingAudioArchive.decrypt(archive: archive, destination: destination, key: Data(repeating: 0, count: 32)))
        XCTAssertEqual(try Data(contentsOf: destination), prior)
        var corrupted = try Data(contentsOf: archive)
        corrupted[corrupted.count - 1] ^= 1
        try corrupted.write(to: archive)
        XCTAssertThrowsError(try MeetingAudioArchive.decrypt(archive: archive, destination: destination, key: key))
        XCTAssertEqual(try Data(contentsOf: destination), prior)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["audio.enc", "original.m4a", "recovered.m4a"])
        XCTAssertThrowsError(try MeetingAudioArchive.decrypt(archive: archive, destination: archive, key: key))
    }

    func testCancelledTaskCanEncryptAndVerifyForSafeCleanup() async throws {
        let source = directory.appendingPathComponent("original.m4a")
        let archive = directory.appendingPathComponent("audio.enc")
        try Data(repeating: 0xA5, count: 1_200_000).write(to: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
            try MeetingAudioArchive.verify(archive: archive, key: key)
        }
        try await task.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testCancelledDecryptionLeavesNoPlaintextOutput() async throws {
        let source = directory.appendingPathComponent("original.m4a")
        let archive = directory.appendingPathComponent("audio.enc")
        let destination = directory.appendingPathComponent("recovered.m4a")
        try Data(repeating: 0xA5, count: 1_200_000).write(to: source)
        try MeetingAudioArchive.encrypt(source: source, destination: archive, key: key)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try MeetingAudioArchive.decrypt(archive: archive, destination: destination, key: key)
        }
        do {
            try await task.value
            XCTFail("Cancelled decryption must not publish plaintext")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["audio.enc", "original.m4a"])
    }

    func testFailedEncryptionPreservesExistingDestinationAndSource() throws {
        let source = directory.appendingPathComponent("audio.m4a")
        let destination = directory.appendingPathComponent("audio.enc")
        let data = Data([1, 2, 3])
        try data.write(to: source)
        try data.write(to: destination)
        XCTAssertThrowsError(try MeetingAudioArchive.encrypt(source: source, destination: destination, key: Data()))
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertEqual(try Data(contentsOf: destination), data)
        XCTAssertThrowsError(try MeetingAudioArchive.encrypt(source: source, destination: source, key: key))
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }
}
