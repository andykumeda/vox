import Foundation

/// Persists every dictation WAV to disk before transcription so the source
/// audio survives gating, hallucination guards, network errors, or crashes.
/// Files are written to `~/Library/Application Support/Vox/Recordings/`
/// with an ISO8601 timestamp + short UUID. Retention is not enforced; the
/// user can prune manually.
public enum RecordingArchive {
    public static func directory() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Writes the WAV blob and returns the file URL. Returns nil on failure.
    @discardableResult
    public static func save(wav: Data, mode: String, at date: Date = Date()) -> URL? {
        guard !wav.isEmpty else { return nil }
        let dir = directory()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let shortID = UUID().uuidString.prefix(8)
        let url = dir.appendingPathComponent("\(stamp)_\(mode)_\(shortID).wav")

        do {
            try wav.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
