import Foundation

/// Service defaults live in a resource, not request-building code. Environment
/// overrides win over saved Settings values; invalid overrides fail closed.
public enum ServiceConfiguration {
    public enum Key: String, CaseIterable, Sendable {
        case dictationProvider
        case cleanupProvider
        case meetingProvider
        case summaryProvider
        case miniDictationModel
        case whisperDictationModel
        case temperature
        case requestMaxAttempts
        case requestRetryDelay
        case meetingRetryBudget
        case meetingRetryDelays
        case meetingChunkDuration
        case openaiTranscriptionURL
        case openrouterTranscriptionURL
        case openaiChatURL
        case openrouterChatURL
        case deepgramURL
        case openaiDictationModel
        case openrouterDictationModel
        case openaiCleanupModel
        case openrouterCleanupModel
        case openaiSummaryModel
        case openrouterSummaryModel
        case meetingModel
        case openrouterMeetingModel
        case openrouterMeetingProviderOptions
        case openrouterMeetingUSDPerHour
        case language
        case dictationTimeout
        case dictationMaximumTimeout
        case dictationTimeoutPerAudioSecond
        case dictationTimeoutPadding
        case cleanupTimeout
        case summaryTimeout
        case meetingTimeout
        case deepgramTimeout
        case cleanupMaxTokens
        case summaryMaxTokens
        case summaryMaxCharacters
        case miniUSDPerMinute
        case fullUSDPerMinute
        case whisperUSDPerMinute
        case openrouterUSDPerMinute
        case deepgramUSDPerHour
        case meetingUSDPerHour

        public var environmentName: String {
            "VOX_" + rawValue
                .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
                .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression).uppercased()
        }
        public var settingsName: String {
            switch self {
            case .dictationProvider, .cleanupProvider, .summaryProvider, .meetingProvider: return rawValue
            default: return "service." + rawValue
            }
        }
        public var isURL: Bool { rawValue.hasSuffix("URL") }
        public var isNumber: Bool {
            switch self {
            case .temperature: return true
            case .requestMaxAttempts: return true
            case .requestRetryDelay: return true
            case .meetingRetryBudget: return true
            case .meetingChunkDuration: return true
            case .dictationTimeout: return true
            case .dictationMaximumTimeout: return true
            case .dictationTimeoutPerAudioSecond: return true
            case .dictationTimeoutPadding: return true
            case .cleanupTimeout: return true
            case .summaryTimeout: return true
            case .meetingTimeout: return true
            case .deepgramTimeout: return true
            case .cleanupMaxTokens: return true
            case .summaryMaxTokens: return true
            case .summaryMaxCharacters: return true
            case .miniUSDPerMinute: return true
            case .fullUSDPerMinute: return true
            case .whisperUSDPerMinute: return true
            case .openrouterUSDPerMinute: return true
            case .deepgramUSDPerHour: return true
            case .meetingUSDPerHour, .openrouterMeetingUSDPerHour: return true
            default: return false
            }
        }
    }

    public struct InvalidValue: LocalizedError {
        public let key: Key
        public init(key: Key) { self.key = key }
        public var errorDescription: String? { "Invalid service setting: \(key.rawValue). Check Settings or \(key.environmentName)." }
    }

    private static let defaults: [String: String] = {
        // A missing packaged resource is a build defect, never a reason to
        // silently route private content to a different service.
        guard let url = Bundle.module.url(forResource: "service-defaults", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data)
        else { preconditionFailure("Missing service-defaults.json") }
        return values
    }()

    public static func defaultValue(_ key: Key) -> String { defaults[key.rawValue]! }

    public static func value(_ key: Key, environment: [String: String] = ProcessInfo.processInfo.environment,
                             settings: UserDefaults = .standard) -> String {
        environment[key.environmentName] ?? settings.string(forKey: key.settingsName) ?? defaultValue(key)
    }

    public static func validate(_ value: String, for key: Key) throws {
        guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { throw InvalidValue(key: key) }
        if key == .dictationProvider {
            guard DictationProvider(rawValue: value) != nil else { throw InvalidValue(key: key) }
        } else if key == .meetingProvider {
            guard ["automatic", "deepgram", "openai", "openrouter"].contains(value) else { throw InvalidValue(key: key) }
        } else if key == .cleanupProvider || key == .summaryProvider {
            guard value == "followDictation" || DictationProvider(rawValue: value) != nil else { throw InvalidValue(key: key) }
        } else if key == .openrouterMeetingProviderOptions {
            guard let data = value.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw InvalidValue(key: key) }
        } else if key == .meetingRetryDelays {
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ Double($0).map { $0.isFinite && $0 > 0 && $0 <= Double(Int32.max) } == true }) else { throw InvalidValue(key: key) }
        } else if key.isURL {
            guard let url = URL(string: value), url.scheme == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw InvalidValue(key: key) }
        } else if key.isNumber {
            guard let number = Double(value), number.isFinite, number >= 0,
                  (key.rawValue.contains("USD") || key == .temperature || number > 0), number <= Double(Int32.max) else { throw InvalidValue(key: key) }
            if key.rawValue.contains("Max") {
                guard number.rounded() == number, number <= Double(Int32.max) else { throw InvalidValue(key: key) }
            }
        } else {
            guard !value.contains("\n"), !value.contains("\r") else { throw InvalidValue(key: key) }
        }
    }

    public static func string(_ key: Key) throws -> String {
        let result = value(key)
        try validate(result, for: key)
        return result
    }
    public static func url(_ key: Key) throws -> URL { URL(string: try string(key))! }
    public static func number(_ key: Key) throws -> Double { Double(try string(key))! }
    // For display/estimates only. Request paths use the throwing accessors.
    public static func estimate(_ key: Key) -> Double { (try? number(key)) ?? Double(defaultValue(key))! }

    public static func save(_ values: [Key: String], settings: UserDefaults = .standard) throws {
        for (key, value) in values where !value.isEmpty { try validate(value, for: key) }
        for (key, value) in values {
            if value.isEmpty { settings.removeObject(forKey: key.settingsName) }
            else { settings.set(value, forKey: key.settingsName) }
        }
    }
}

public struct ChatServiceConfiguration: Sendable {
    public let endpoint: URL
    public let model: String
    public let timeout: TimeInterval
    public let maxTokens: Int
    public let temperature: Double

    public static func resolve(provider: DictationProvider, summary: Bool = false) throws -> Self {
        let router = provider == .openrouter
        return try Self(
            endpoint: ServiceConfiguration.url(router ? .openrouterChatURL : .openaiChatURL),
            model: ServiceConfiguration.string(summary
                ? (router ? .openrouterSummaryModel : .openaiSummaryModel)
                : (router ? .openrouterCleanupModel : .openaiCleanupModel)),
            timeout: ServiceConfiguration.number(summary ? .summaryTimeout : .cleanupTimeout),
            maxTokens: Int(ServiceConfiguration.number(summary ? .summaryMaxTokens : .cleanupMaxTokens)),
            temperature: ServiceConfiguration.number(.temperature)
        )
    }
}
