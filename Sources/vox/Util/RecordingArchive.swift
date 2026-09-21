import Foundation

/// Filesystem helpers for temporary dictation audio.
/// `AudioRecorder` streams WAV bytes here while capturing. Terminal processing
/// deletes each recording; launch cleanup deletes any crash leftovers.
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
