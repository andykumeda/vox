import Foundation

public enum Scope: String, Codable, CaseIterable, Sendable {
    case command
    case prose
    case both
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var spoken: String
    public var replacement: String
    public var mode: Scope
    public var startsWith: Bool
    public var caseInsensitive: Bool
    public var enabled: Bool
    public var isBuiltIn: Bool

    public init(
        id: String,
        spoken: String,
        replacement: String,
        mode: Scope,
        startsWith: Bool = false,
        caseInsensitive: Bool = true,
        enabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.spoken = spoken
        self.replacement = replacement
        self.mode = mode
        self.startsWith = startsWith
        self.caseInsensitive = caseInsensitive
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }
}
