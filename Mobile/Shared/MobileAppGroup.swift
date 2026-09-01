import Foundation
import VoxCore

enum MobileAppGroup {
    static let identifier = "group.com.andykumeda.vox"
    static let exchangeFilename = "dictation-exchange.json"

    static func containerURL(fileManager: FileManager = .default) throws -> URL {
        guard let url = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw MobileAppGroupError.containerUnavailable
        }
        return url
    }

    static func exchangeStore() throws -> MobileDictationExchangeStore {
        MobileDictationExchangeStore(
            fileURL: try containerURL().appendingPathComponent(exchangeFilename)
        )
    }

    static func dictionaryURL() throws -> URL {
        try containerURL()
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    static func historyURL() throws -> URL {
        try containerURL()
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func recordingsDirectory() throws -> URL {
        let url = try containerURL().appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum MobileAppGroupError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        "Vox could not access its shared keyboard container. Reinstall the app and keyboard."
    }
}
