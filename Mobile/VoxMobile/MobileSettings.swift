import Foundation
import VoxCore

enum MobileCleanupProvider: String, CaseIterable {
    case followDictation
    case openai
    case openrouter

    var displayName: String {
        switch self {
        case .followDictation: return "Follow dictation provider"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        }
    }
}

@MainActor
final class MobileSettings: ObservableObject {
    private enum Key {
        static let smartCleanup = "mobile.smartCleanup"
        static let dictationProvider = "mobile.dictationProvider"
        static let cleanupProvider = "mobile.cleanupProvider"
    }

    static let serviceKeys: [ServiceConfiguration.Key] = [
        .openaiTranscriptionURL, .openrouterTranscriptionURL,
        .openaiDictationModel, .openrouterDictationModel,
        .openaiChatURL, .openrouterChatURL,
        .openaiCleanupModel, .openrouterCleanupModel,
        .language, .dictationTimeout, .dictationMaximumTimeout,
        .dictationTimeoutPerAudioSecond, .dictationTimeoutPadding,
        .cleanupTimeout, .cleanupMaxTokens, .temperature,
        .requestMaxAttempts, .requestRetryDelay,
    ]

    private let defaults: UserDefaults
    private static let keychainService = "com.andykumeda.vox.ios"

    @Published var smartCleanupEnabled: Bool {
        didSet { defaults.set(smartCleanupEnabled, forKey: Key.smartCleanup) }
    }
    @Published var dictationProvider: DictationProvider {
        didSet { defaults.set(dictationProvider.rawValue, forKey: Key.dictationProvider) }
    }
    @Published var cleanupProvider: MobileCleanupProvider {
        didSet { defaults.set(cleanupProvider.rawValue, forKey: Key.cleanupProvider) }
    }
    struct InvalidProvider: LocalizedError {
        let setting: String
        var errorDescription: String? {
            "Invalid \(setting) provider. Choose a supported provider in Settings."
        }
    }

    private static func providerValue(_ key: ServiceConfiguration.Key, mobileKey: String,
                                      defaults: UserDefaults) -> String {
        ProcessInfo.processInfo.environment[key.environmentName]
            ?? defaults.string(forKey: mobileKey)
            ?? ServiceConfiguration.defaultValue(key)
    }

    func validatedDictationProvider() throws -> DictationProvider {
        let raw = Self.providerValue(.dictationProvider, mobileKey: Key.dictationProvider, defaults: defaults)
        guard let provider = DictationProvider(rawValue: raw) else {
            throw InvalidProvider(setting: "dictation")
        }
        return provider
    }

    func validatedCleanupProvider() throws -> DictationProvider {
        let raw = Self.providerValue(.cleanupProvider, mobileKey: Key.cleanupProvider, defaults: defaults)
        switch raw {
        case MobileCleanupProvider.followDictation.rawValue:
            return try validatedDictationProvider()
        case MobileCleanupProvider.openai.rawValue: return .openai
        case MobileCleanupProvider.openrouter.rawValue: return .openrouter
        default: throw InvalidProvider(setting: "cleanup")
        }
    }

    @Published var apiKey: String = ""
    @Published var openrouterAPIKey: String = ""
    @Published var saveMessage: String?
    @Published var serviceValues: [ServiceConfiguration.Key: String] = [:]
    @Published var serviceSaveMessage: String?

    init(defaults: UserDefaults = UserDefaults(suiteName: MobileAppGroup.identifier) ?? .standard) {
        self.defaults = defaults
        smartCleanupEnabled = defaults.object(forKey: Key.smartCleanup) as? Bool ?? true
        dictationProvider = DictationProvider(rawValue: Self.providerValue(.dictationProvider, mobileKey: Key.dictationProvider, defaults: defaults))
            ?? DictationProvider(rawValue: ServiceConfiguration.defaultValue(.dictationProvider))!
        cleanupProvider = MobileCleanupProvider(rawValue: Self.providerValue(.cleanupProvider, mobileKey: Key.cleanupProvider, defaults: defaults))
            ?? MobileCleanupProvider(rawValue: ServiceConfiguration.defaultValue(.cleanupProvider))!
        apiKey = readAPIKey(provider: .openai) ?? ""
        openrouterAPIKey = readAPIKey(provider: .openrouter) ?? ""
        serviceValues = Dictionary(uniqueKeysWithValues: Self.serviceKeys.map { ($0, ServiceConfiguration.value($0)) })
    }

    func saveAPIKey(provider: DictationProvider) {
        do {
            let entered = provider == .openai ? apiKey : openrouterAPIKey
            let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
            let keychain = Self.keychain(for: provider)
            if trimmed.isEmpty {
                try keychain.delete()
                saveMessage = "\(provider.displayName) API key removed."
            } else {
                try keychain.save(trimmed)
                if provider == .openai { apiKey = trimmed }
                else { openrouterAPIKey = trimmed }
                saveMessage = "\(provider.displayName) API key saved securely."
            }
        } catch {
            saveMessage = "Could not save the \(provider.displayName) API key: \(error.localizedDescription)"
        }
    }

    func saveServiceConfiguration() {
        do {
            try ServiceConfiguration.save(serviceValues)
            serviceSaveMessage = "Service settings saved. Environment overrides take precedence."
        } catch {
            serviceSaveMessage = error.localizedDescription
        }
    }

    private nonisolated static func keychain(for provider: DictationProvider) -> KeychainStore {
        KeychainStore(service: keychainService, account: provider.keychainAccount)
    }

    nonisolated func readAPIKey(provider: DictationProvider) -> String? {
        Self.keychain(for: provider).read()
    }
}
