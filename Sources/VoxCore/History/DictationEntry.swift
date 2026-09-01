import Foundation

public struct DictationEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let mode: String
    public let durationSec: Double
    public let wordCount: Int
    public let text: String
    public let rawText: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: String,
        durationSec: Double,
        wordCount: Int,
        text: String,
        rawText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.durationSec = durationSec
        self.wordCount = wordCount
        self.text = text
        self.rawText = rawText ?? text
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, mode, durationSec, wordCount, text, rawText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mode = try container.decode(String.self, forKey: .mode)
        durationSec = try container.decode(Double.self, forKey: .durationSec)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        text = try container.decode(String.self, forKey: .text)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? text
    }
}
