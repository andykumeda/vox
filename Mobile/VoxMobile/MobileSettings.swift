import Foundation
import VoxCore

@MainActor
final class MobileSettings: ObservableObject {
    private enum Key {
        static let smartCleanup = "mobile.smartCleanup"
    }

    private let defaults: UserDefaults
    private let keychain = KeychainStore(service: "com.andykumeda.vox.ios")

    @Published var smartCleanupEnabled: Bool {
        didSet { defaults.set(smartCleanupEnabled, forKey: Key.smartCleanup) }
    }

    @Published var apiKey: String = ""
    @Published var saveMessage: String?

    init(defaults: UserDefaults = UserDefaults(suiteName: MobileAppGroup.identifier) ?? .standard) {
        self.defaults = defaults
        smartCleanupEnabled = defaults.object(forKey: Key.smartCleanup) as? Bool ?? true
        apiKey = keychain.read() ?? ""
    }

    func saveAPIKey() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try keychain.delete()
                saveMessage = "API key removed."
            } else {
                try keychain.save(trimmed)
                apiKey = trimmed
                saveMessage = "API key saved securely."
            }
        } catch {
            saveMessage = "Could not save the API key: \(error.localizedDescription)"
        }
    }

    nonisolated func readAPIKey() -> String? {
        KeychainStore(service: "com.andykumeda.vox.ios").read()
    }
}
