import XCTest
@testable import vox

final class RecordingArchiveTests: XCTestCase {
    func testRepairsZeroSizedHeaderAfterCrash() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("crashed.wav")
        // Write a placeholder header (sizes = 0) plus 4096 PCM bytes — the
        // exact state a process crash mid-capture would leave behind.
        var file = makePlaceholderHeader()
        file.append(Data(count: 4096))
        try file.write(to: url)

        RecordingArchive.repairWAVHeaderIfNeeded(at: url)

        let patched = try Data(contentsOf: url)
        let riffSize = patched.subdata(in: 4..<8)
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let dataSize = patched.subdata(in: 40..<44)
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataSize, 4096)
        XCTAssertEqual(riffSize, 36 + 4096)
    }

    func testLeavesValidFileAlone() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("ok.wav")
        var file = makePlaceholderHeader(pcmSize: 1024)
        file.append(Data(count: 1024))
        try file.write(to: url)
        let originalSize = file.subdata(in: 40..<44)
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        RecordingArchive.repairWAVHeaderIfNeeded(at: url)

        let after = try Data(contentsOf: url)
        let dataSize = after.subdata(in: 40..<44)
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataSize, originalSize)
    }

    private func makePlaceholderHeader(pcmSize: UInt32 = 0) -> Data {
        var h = Data()
        let chunkSize: UInt32 = pcmSize == 0 ? 36 : 36 + pcmSize
        h.append(contentsOf: "RIFF".utf8); h.appendLE(chunkSize)
        h.append(contentsOf: "WAVE".utf8)
        h.append(contentsOf: "fmt ".utf8); h.appendLE(UInt32(16))
        h.appendLE(UInt16(1)); h.appendLE(UInt16(1))
        h.appendLE(UInt32(16_000)); h.appendLE(UInt32(32_000))
        h.appendLE(UInt16(2)); h.appendLE(UInt16(16))
        h.append(contentsOf: "data".utf8); h.appendLE(pcmSize)
        return h
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
