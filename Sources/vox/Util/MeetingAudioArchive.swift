import Foundation

/// Block-encrypted meeting audio; each block binds its archive, length and order.
enum MeetingAudioArchive {
    private static let magic = Data("VOXAUD1".utf8)
    private static let blockSize = 1_048_576
    private static let contextSize = 7 + 36 + 8

    static func encrypt(source: URL, destination: URL, key: Data) throws {
        guard source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let cipher = try TranscriptCipher(keyData: key)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        try input.seek(toOffset: 0)
        let context = magic + Data(UUID().uuidString.utf8) + bytes(size)
        let candidate = destination.deletingLastPathComponent()
            .appendingPathComponent(".audio-\(UUID().uuidString).candidate")
        defer { try? FileManager.default.removeItem(at: candidate) }
        guard FileManager.default.createFile(
            atPath: candidate.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: candidate)
        defer { try? output.close() }
        try writeFrame(cipher.seal(context), to: output)
        var remaining = size
        var index: UInt64 = 0
        while remaining > 0 {
            let count = Int(min(UInt64(blockSize), remaining))
            let data = try readExactly(count, from: input)
            try writeFrame(cipher.seal(context + bytes(index) + data), to: output)
            remaining -= UInt64(count)
            index += 1
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try output.synchronize()
        try output.close()
        try verify(archive: candidate, key: key)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: candidate)
        } else {
            try FileManager.default.moveItem(at: candidate, to: destination)
        }
    }

    static func verify(archive: URL, key: Data) throws {
        let cipher = try TranscriptCipher(keyData: key)
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let context = try cipher.open(readFrame(from: input))
        guard context.count == contextSize, context.starts(with: magic),
              let archiveID = String(data: context.dropFirst(magic.count).prefix(36), encoding: .utf8),
              UUID(uuidString: archiveID) != nil else {
            throw TranscriptEncryptionError.invalidEnvelope
        }
        var remaining = integer(context.suffix(8))
        var index: UInt64 = 0
        while remaining > 0 {
            let count = Int(min(UInt64(blockSize), remaining))
            let plaintext = try cipher.open(readFrame(from: input))
            guard plaintext.count == contextSize + 8 + count,
                  plaintext.prefix(contextSize) == context,
                  integer(plaintext.dropFirst(contextSize).prefix(8)) == index else {
                throw TranscriptEncryptionError.invalidEnvelope
            }
            remaining -= UInt64(count)
            index += 1
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else {
            throw TranscriptEncryptionError.invalidEnvelope
        }
    }

    private static func bytes(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func integer(_ data: Data) -> UInt64 {
        data.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func writeFrame(_ data: Data, to output: FileHandle) throws {
        try output.write(contentsOf: bytes(UInt64(data.count)))
        try output.write(contentsOf: data)
    }

    private static func readFrame(from input: FileHandle) throws -> Data {
        let count = integer(try readExactly(8, from: input))
        guard count > 0, count <= blockSize + contextSize + 8 + 64 else {
            throw TranscriptEncryptionError.invalidEnvelope
        }
        return try readExactly(Int(count), from: input)
    }

    private static func readExactly(_ count: Int, from input: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let next = try input.read(upToCount: count - result.count), !next.isEmpty else {
                throw TranscriptEncryptionError.invalidEnvelope
            }
            result.append(next)
        }
        return result
    }
}
