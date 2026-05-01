import Foundation

/// Filesystem helpers for the on-disk dictation recording archive.
/// `AudioRecorder` streams WAV bytes into this directory while capturing.
/// Files written here survive transcription failures, silence gating,
/// hallucination guards, and process crashes (see `repairOrphans`).
public enum RecordingArchive {
    public static func directory() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Picks a fresh URL inside the archive directory and ensures the parent exists.
    public static func newRecordingURL(mode: String, at date: Date = Date()) throws -> URL {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let shortID = UUID().uuidString.prefix(8)
        return dir.appendingPathComponent("\(stamp)_\(mode)_\(shortID).wav")
    }

    /// Patches WAV size fields on any file in the archive whose RIFF/data chunk
    /// sizes are still zero. Such files were left behind by a crash mid-recording.
    /// Without this, decoders see a zero-length file even though the PCM bytes
    /// are present on disk. Safe to call repeatedly; idempotent.
    public static func repairOrphans() {
        let dir = directory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return
        }
        for url in entries where url.pathExtension.lowercased() == "wav" {
            repairWAVHeaderIfNeeded(at: url)
        }
    }

    /// Inspects a WAV file's header. If RIFF/data chunk sizes are zero but the
    /// file actually has PCM bytes on disk, rewrites the size fields based on
    /// the real file size. Leaves correctly-finalised files alone.
    static func repairWAVHeaderIfNeeded(at url: URL) {
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 44), header.count == 44 else { return }
        // Validate it's a WAV we wrote ("RIFF....WAVE...")
        let riff = header.subdata(in: 0..<4)
        let wave = header.subdata(in: 8..<12)
        guard riff == Data("RIFF".utf8), wave == Data("WAVE".utf8) else { return }

        let dataChunkSize = header.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        if dataChunkSize != 0 { return }  // already finalised

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard fileSize > 44 else { return }
        let pcmBytes = UInt32(min(fileSize - 44, UInt64(UInt32.max)))
        let riffSize = UInt32(min(fileSize - 8, UInt64(UInt32.max)))

        try? handle.seek(toOffset: 4)
        try? handle.write(contentsOf: littleEndianBytes(riffSize))
        try? handle.seek(toOffset: 40)
        try? handle.write(contentsOf: littleEndianBytes(pcmBytes))
        dlog("RecordingArchive: repaired orphan \(url.lastPathComponent) (\(pcmBytes) PCM bytes)")
    }

    static func littleEndianBytes(_ v: UInt32) -> [UInt8] {
        let le = v.littleEndian
        return [UInt8(le & 0xff), UInt8((le >> 8) & 0xff), UInt8((le >> 16) & 0xff), UInt8((le >> 24) & 0xff)]
    }

    /// Deletes every WAV in the archive whose modification date is older than
    /// `cutoff`. Returns the number of files removed.
    @discardableResult
    public static func purgeOlderThan(_ cutoff: Date) -> Int {
        let dir = directory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        var removed = 0
        for url in entries where url.pathExtension.lowercased() == "wav" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            if mtime < cutoff {
                if (try? fm.removeItem(at: url)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }

    /// Total size in bytes of every WAV currently in the archive directory.
    public static func diskBytes() -> UInt64 {
        let dir = directory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return entries.reduce(into: UInt64(0)) { acc, url in
            guard url.pathExtension.lowercased() == "wav" else { return }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            acc += UInt64(size)
        }
    }
}
