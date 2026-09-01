import Foundation

public enum CleanupDictionaryProtection {
    public static func apply(
        _ text: String,
        mode: TranscriptionMode,
        entries: [DictionaryEntry]
    ) -> String {
        guard mode == .prose, !text.contains("\n") else { return text }
        return DictionaryMatcher.apply(entries: entries, to: text, scope: .prose)
    }
}
