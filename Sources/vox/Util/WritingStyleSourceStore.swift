import Foundation

enum WritingStyleSourceError: Error, LocalizedError, Equatable {
    case invalidBookmark
    case fileTooLarge
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidBookmark: return "The linked style file bookmark is invalid."
        case .fileTooLarge: return "The style file exceeds the 256 KB limit."
        case .invalidUTF8: return "The style file must be UTF-8 Markdown."
        }
    }
}

final class WritingStyleSourceStore {
    static let shared = WritingStyleSourceStore()
    static let maximumBytes = 256 * 1024

    typealias BookmarkMaker = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> (url: URL, stale: Bool)

    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let makeBookmark: BookmarkMaker
    private let resolveBookmark: BookmarkResolver

    init(
        defaults: UserDefaults = .standard,
        bookmarkKey: String = "writingStyleFileBookmark",
        makeBookmark: @escaping BookmarkMaker = { url in
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: [.nameKey],
                relativeTo: nil
            )
        },
        resolveBookmark: @escaping BookmarkResolver = { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        }
    ) {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
    }

    var hasLinkedFile: Bool { defaults.data(forKey: bookmarkKey) != nil }

    func select(_ url: URL) throws {
        defaults.set(try makeBookmark(url), forKey: bookmarkKey)
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    func linkedURL() throws -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }
        let resolved = try resolveBookmark(bookmark)
        if resolved.stale {
            defaults.set(try makeBookmark(resolved.url), forKey: bookmarkKey)
        }
        return resolved.url
    }

    func loadExternal() throws -> String? {
        guard let url = try linkedURL() else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: Self.maximumBytes + 1) else { return "" }
        guard data.count <= Self.maximumBytes else { throw WritingStyleSourceError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WritingStyleSourceError.invalidUTF8
        }
        return text
    }

    func activeInstructions(fallback: @autoclosure () -> String) -> String {
        do {
            return try loadExternal() ?? fallback()
        } catch {
            dlog("writing style file unavailable; using inline fallback error=\(error.localizedDescription)")
            return fallback()
        }
    }
}
