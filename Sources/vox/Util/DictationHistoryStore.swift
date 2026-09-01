import Foundation

public extension Notification.Name {
    static let dictationHistoryDidChange = Notification.Name("vox.dictationHistoryDidChange")
}

/// Persists completed dictations in one authenticated encrypted envelope.
/// Legacy plaintext JSON is migrated only after the encrypted replacement can
/// be decrypted and decoded successfully.
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
    private let legacyURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keyProvider: () throws -> Data
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
            legacyURL: fileURL == Self.defaultURL() ? Self.legacyURL() : nil,
            decoder: decoder,
            keyProvider: { try TranscriptEncryptionKeyStore.shared.loadOrCreate() },
            log: { message in dlog(message) }
        )
    }

    init(
        fileURL: URL,
        legacyURL: URL? = nil,
        decoder: JSONDecoder,
        keyProvider: @escaping () throws -> Data,
        log: @escaping (String) -> Void
    ) {
        self.fileURL = fileURL
        self.legacyURL = legacyURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = decoder
        self.keyProvider = keyProvider
        self.log = log
    }

    public static func defaultURL() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("DictationHistory", isDirectory: true)
            .appendingPathComponent("history.enc")
    }

    public static func legacyURL() -> URL {
        defaultURL().deletingLastPathComponent().appendingPathComponent("history.json")
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

    /// Appends an entry and waits for the write to finish.
    /// Returns `false` when the existing file is unreadable/corrupt or the write fails;
    /// the on-disk file is left untouched in those cases.
    @discardableResult
    public func record(_ entry: DictationEntry) -> Bool {
        queue.sync {
            guard case .success(var entries) = self.readAll() else { return false }
            entries.append(entry)
            entries = self.applyRetention(entries)
            guard self.writeAll(entries) else { return false }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dictationHistoryDidChange, object: nil
                )
            }
            return true
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
        if !FileManager.default.fileExists(atPath: fileURL.path),
           let legacyURL,
           FileManager.default.fileExists(atPath: legacyURL.path) {
            return migrateLegacyFile(at: legacyURL)
        }
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
                let plaintext: Data
                if TranscriptCipher.isEncryptedEnvelope(data) {
                    let cipher = try TranscriptCipher(keyData: keyProvider())
                    plaintext = try cipher.open(data)
                } else {
                    // A custom/older path may itself contain plaintext. Treat it
                    // as an in-place migration, preserving it if encryption fails.
                    plaintext = data
                }
                let entries = try decoder.decode([DictationEntry].self, from: plaintext)
                if !TranscriptCipher.isEncryptedEnvelope(data) {
                    return writeAll(entries) ? .success(entries) : .failure
                }
                removeVerifiedLegacyPlaintextIfPresent()
                let result = ReadResult.success(entries)
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
            let plaintext = try encoder.encode(entries)
            let cipher = try TranscriptCipher(keyData: keyProvider())
            let data = try cipher.seal(plaintext)
            let candidateURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".history-\(UUID().uuidString).candidate")
            defer { try? FileManager.default.removeItem(at: candidateURL) }
            try data.write(to: candidateURL, options: .atomic)
            let verified = try decoder.decode(
                [DictationEntry].self,
                from: cipher.open(Data(contentsOf: candidateURL))
            )
            guard try encoder.encode(verified) == plaintext else {
                log("DictationHistoryStore verification failed; encrypted file did not round-trip")
                return false
            }
            try installVerifiedCandidate(candidateURL)
            readCache = ReadCache(data: data, result: .success(entries))
            return true
        } catch {
            log("DictationHistoryStore write failed: \(error)")
            return false
        }
    }

    private func migrateLegacyFile(at url: URL) -> ReadResult {
        do {
            let data = try Data(contentsOf: url)
            let entries = try decoder.decode([DictationEntry].self, from: data)
            guard writeAll(entries) else { return .failure }
            removeVerifiedLegacyPlaintextIfPresent()
            return .success(entries)
        } catch {
            log("DictationHistoryStore legacy migration failed; preserving plaintext file: \(error)")
            return .failure
        }
    }

    private func installVerifiedCandidate(_ candidateURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: candidateURL)
        } else {
            try fileManager.moveItem(at: candidateURL, to: fileURL)
        }
    }

    private func removeVerifiedLegacyPlaintextIfPresent() {
        guard let legacyURL,
              legacyURL != fileURL,
              FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: legacyURL)
            log("DictationHistoryStore removed verified legacy plaintext history")
        } catch {
            log("DictationHistoryStore could not remove legacy plaintext; will retry: \(error)")
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
