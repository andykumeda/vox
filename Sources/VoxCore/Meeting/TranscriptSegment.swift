import Foundation

public enum SegmentSource: String, Codable, Sendable {
    case remote
    case local
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let text: String
    public let source: SegmentSource
    public let speakerID: Int?

    public init(
        startTime: Double,
        endTime: Double,
        text: String,
        source: SegmentSource = .remote,
        speakerID: Int? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.source = source
        self.speakerID = speakerID
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, text, source, speakerID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try container.decode(Double.self, forKey: .startTime)
        endTime = try container.decode(Double.self, forKey: .endTime)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decodeIfPresent(SegmentSource.self, forKey: .source) ?? .remote
        speakerID = try container.decodeIfPresent(Int.self, forKey: .speakerID)
    }
}
