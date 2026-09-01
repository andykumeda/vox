import Foundation
import VoxCore

@MainActor
final class MobileHistoryStore: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []
    private let fileURL: URL?

    init(fileURL: URL? = try? MobileAppGroup.historyURL()) {
        self.fileURL = fileURL
        reload()
    }

    func reload() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if TranscriptCipher.isEncryptedEnvelope(data),
           let key = try? TranscriptEncryptionKeyStore.shared.loadOrCreate(),
           let cipher = try? TranscriptCipher(keyData: key),
           let plaintext = try? cipher.open(data) {
            entries = (try? decoder.decode([DictationEntry].self, from: plaintext)) ?? []
        } else {
            // Legacy plaintext migration. persist() replaces the file only if
            // encryption and the atomic write both succeed.
            entries = (try? decoder.decode([DictationEntry].self, from: data)) ?? []
            if !entries.isEmpty { persist() }
        }
    }

    func record(text: String, rawText: String, durationSec: Double) {
        let entry = DictationEntry(
            mode: "prose",
            durationSec: durationSec,
            wordCount: text.split(whereSeparator: \.isWhitespace).count,
            text: text,
            rawText: rawText
        )
        entries.append(entry)
        persist()
    }

    func delete(at offsets: IndexSet) {
        let descending = offsets.sorted(by: >)
        for index in descending where entries.indices.contains(index) {
            entries.remove(at: index)
        }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let plaintext = try encoder.encode(entries)
            let key = try TranscriptEncryptionKeyStore.shared.loadOrCreate()
            let cipher = try TranscriptCipher(keyData: key)
            try cipher.seal(plaintext).write(to: fileURL, options: .atomic)
        } catch {
            dlog("iOS history write failed: \(error.localizedDescription)")
        }
    }
}
