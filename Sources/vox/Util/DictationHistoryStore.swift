import Foundation

public struct DictationEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let mode: String
    public let durationSec: Double
    public let wordCount: Int
    public let text: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: String,
        durationSec: Double,
        wordCount: Int,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.durationSec = durationSec
        self.wordCount = wordCount
        self.text = text
    }
}

public extension Notification.Name {
    static let dictationHistoryDidChange = Notification.Name("vox.dictationHistoryDidChange")
}

/// Persists every completed dictation to a single JSON file under
/// `~/Library/Application Support/Vox/DictationHistory/history.json`.
/// Atomic writes via `Data.write(.atomic)`. Retention is enforced on every record()
/// based on `AppSettings.dictationHistoryRetention`.
public final class DictationHistoryStore {
    public static let shared = DictationHistoryStore()

    private enum ReadResult {
        case success([DictationEntry])
        case failure
    }

    private struct ReadCache {
        let data: Data
        let result: ReadResult
    }

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "vox.dictation-history")
    /// Accessed only from `queue` so decoded entries and failure state stay
    /// consistent with the exact file bytes that produced them.
    private var readCache: ReadCache?

    public convenience init(fileURL: URL = DictationHistoryStore.defaultURL()) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.init(
            fileURL: fileURL,
            decoder: decoder,
            log: { message in dlog(message) }
        )
    }

    init(
        fileURL: URL,
        decoder: JSONDecoder,
        log: @escaping (String) -> Void
    ) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = decoder
        self.log = log
    }

    public static func defaultURL() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("DictationHistory", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func list() -> [DictationEntry] {
        queue.sync {
            guard case .success(let entries) = readAll() else { return [] }
            return entries
        }
    }

    public func last() -> DictationEntry? {
        queue.sync {
            guard case .success(let entries) = readAll() else { return nil }
            return entries.last
        }
    }

    public func record(_ entry: DictationEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            guard case .success(var entries) = self.readAll() else { return }
            entries.append(entry)
            entries = self.applyRetention(entries)
            guard self.writeAll(entries) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dictationHistoryDidChange, object: nil
                )
            }
        }
    }

    public func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.writeAll([]) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dictationHistoryDidChange, object: nil
                )
            }
        }
    }

    public func purgeOlderThan(_ date: Date) {
        queue.async { [weak self] in
            guard let self else { return }
            guard case .success(let entries) = self.readAll() else { return }
            let kept = entries.filter { $0.timestamp >= date }
            self.writeAll(kept)
        }
    }

    private func readAll() -> ReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            readCache = nil
            return .success([])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            if let readCache, readCache.data == data {
                return readCache.result
            }
            do {
                let result = ReadResult.success(
                    try decoder.decode([DictationEntry].self, from: data)
                )
                readCache = ReadCache(data: data, result: result)
                return result
            } catch {
                log("DictationHistoryStore decode failed; preserving existing file: \(error)")
                let result = ReadResult.failure
                readCache = ReadCache(data: data, result: result)
                return result
            }
        } catch {
            readCache = nil
            log("DictationHistoryStore read failed; preserving existing file: \(error)")
            return .failure
        }
    }

    @discardableResult
    private func writeAll(_ entries: [DictationEntry]) -> Bool {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            readCache = ReadCache(data: data, result: .success(entries))
            return true
        } catch {
            log("DictationHistoryStore write failed: \(error)")
            return false
        }
    }

    private func applyRetention(_ entries: [DictationEntry]) -> [DictationEntry] {
        let now = Date()
        let cutoff: Date? = {
            switch AppSettings.dictationHistoryRetention {
            case .forever:    return nil
            case .year:       return now.addingTimeInterval(-365 * 86400)
            case .ninetyDays: return now.addingTimeInterval(-90 * 86400)
            case .thirtyDays: return now.addingTimeInterval(-30 * 86400)
            }
        }()
        guard let cutoff else { return entries }
        return entries.filter { $0.timestamp >= cutoff }
    }
}
