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

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "vox.dictation-history")

    public init(fileURL: URL = DictationHistoryStore.defaultURL()) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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
        queue.sync { readAll() }
    }

    public func record(_ entry: DictationEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            var entries = self.readAll()
            entries.append(entry)
            entries = self.applyRetention(entries)
            self.writeAll(entries)
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
            self.writeAll([])
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
            let kept = self.readAll().filter { $0.timestamp >= date }
            self.writeAll(kept)
        }
    }

    private func readAll() -> [DictationEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([DictationEntry].self, from: data)) ?? []
    }

    private func writeAll(_ entries: [DictationEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
