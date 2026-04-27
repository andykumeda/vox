import Foundation
import Combine

/// On-disk envelope for the dictionary file.
public struct DictionaryFileV1: Codable {
    public var schemaVersion: Int
    public var entries: [DictionaryEntry]
}

@MainActor
public final class DictionaryStore: ObservableObject {

    @MainActor
    public static let shared: DictionaryStore = DictionaryStore(
        fileURL: DictionaryStore.defaultFileURL(),
        bundledDefaults: DictionaryDefaults.bundledDefaults
    )

    @Published public private(set) var entries: [DictionaryEntry] = []
    @Published public private(set) var loadError: String?
    @Published public private(set) var saveError: String?

    public let fileURL: URL
    private let bundledDefaults: [DictionaryEntry]

    public init(fileURL: URL, bundledDefaults: [DictionaryEntry]) {
        self.fileURL = fileURL
        self.bundledDefaults = bundledDefaults
    }

    public nonisolated static func defaultFileURL() -> URL {
        guard let userBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("applicationSupportDirectory unavailable — cannot initialize DictionaryStore")
        }
        let base = userBase.appendingPathComponent("Vox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dictionary.json")
    }

    /// Load from disk, seed-merge defaults, write back if mutated.
    public func load() {
        let onDisk = readFile()
        var merged = onDisk.entries

        let presentBuiltinIds = Set(merged.filter(\.isBuiltIn).map(\.id))
        var didMutate = false
        for d in bundledDefaults where !presentBuiltinIds.contains(d.id) {
            merged.append(d)
            didMutate = true
        }

        // Drop duplicate ids — first wins.
        var seen = Set<String>()
        let deduped = merged.filter { e in
            if seen.contains(e.id) { return false }
            seen.insert(e.id)
            return true
        }
        if deduped.count != merged.count {
            merged = deduped
            didMutate = true
        }

        self.entries = merged
        if didMutate {
            try? write(entries: merged)
        }
    }

    public func add(_ entry: DictionaryEntry) {
        let backup = entries
        entries.append(entry)
        do {
            try write(entries: entries)
            saveError = nil
        } catch {
            entries = backup
            saveError = "Could not save dictionary: \(error.localizedDescription)"
        }
    }

    public func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let backup = entries
        entries[idx] = entry
        do {
            try write(entries: entries)
            saveError = nil
        } catch {
            entries = backup
            saveError = "Could not save dictionary: \(error.localizedDescription)"
        }
    }

    public func delete(id: String) {
        let backup = entries
        entries.removeAll { $0.id == id }
        do {
            try write(entries: entries)
            saveError = nil
        } catch {
            entries = backup
            saveError = "Could not save dictionary: \(error.localizedDescription)"
        }
    }

    public func setEnabled(id: String, enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let backup = entries
        entries[idx].enabled = enabled
        do {
            try write(entries: entries)
            saveError = nil
        } catch {
            entries = backup
            saveError = "Could not save dictionary: \(error.localizedDescription)"
        }
    }

    // MARK: - File I/O

    private func readFile() -> DictionaryFileV1 {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadError = nil
            return DictionaryFileV1(schemaVersion: 1, entries: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(DictionaryFileV1.self, from: data)
            if decoded.schemaVersion != 1 {
                loadError = "Unsupported schemaVersion \(decoded.schemaVersion); using defaults."
                return DictionaryFileV1(schemaVersion: 1, entries: bundledDefaults)
            }
            loadError = nil
            return decoded
        } catch {
            loadError = "Could not parse dictionary.json: \(error.localizedDescription)"
            return DictionaryFileV1(schemaVersion: 1, entries: bundledDefaults)
        }
    }

    private func write(entries: [DictionaryEntry]) throws {
        let envelope = DictionaryFileV1(schemaVersion: 1, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        let tmp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        // Replace destination atomically.
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }
}
