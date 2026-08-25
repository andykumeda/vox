import Foundation

public final class CleanupProfileStore {
    public static let shared = CleanupProfileStore(fileURL: CleanupProfileStore.defaultFileURL())

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public nonisolated static func defaultFileURL() -> URL {
        guard let userBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("applicationSupportDirectory unavailable — cannot initialize CleanupProfileStore")
        }
        let base = userBase.appendingPathComponent("Vox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("cleanup-profile.md")
    }

    public func load() -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return "" }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public func save(_ profile: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try profile.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func reset() throws {
        try save("")
    }

    public func ensureFileExists() throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try save("")
        }
    }

    /// Extracts phrases from the deliberately narrow profile syntax used for
    /// deterministic correction triggers, for example:
    /// `Additional trigger: “rather”, “or rather” - should function like “scratch that”`.
    public static func additionalScratchThatTriggers(from profile: String) -> [String] {
        let marker = "additional trigger:"
        guard let markerRange = profile.range(of: marker, options: .caseInsensitive) else {
            return []
        }
        let line = String(profile[markerRange.upperBound...]).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let beforeExplanation = line.components(separatedBy: " - ").first ?? line
        guard let regex = try? NSRegularExpression(pattern: "[\\\"“]([^\\\"”]+)[\\\"”]") else {
            return []
        }
        let ns = beforeExplanation as NSString
        return regex.matches(in: beforeExplanation, range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                guard match.numberOfRanges > 1 else { return nil }
                return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}
