import XCTest
@testable import VoxCore

final class ServiceConfigurationTests: XCTestCase {
    func testEveryDefaultIsPresentAndValid() throws {
        for key in ServiceConfiguration.Key.allCases {
            try ServiceConfiguration.validate(ServiceConfiguration.defaultValue(key), for: key)
        }
    }

    func testEnvironmentWinsOverSettingsAndDefaults() throws {
        let name = "vox-config-test-\(UUID())"
        let settings = UserDefaults(suiteName: name)!
        defer { settings.removePersistentDomain(forName: name) }
        let key = ServiceConfiguration.Key.openrouterChatURL
        XCTAssertEqual(ServiceConfiguration.value(key, environment: [:], settings: settings), ServiceConfiguration.defaultValue(key))
        try ServiceConfiguration.save([key: "https://settings.example/chat"], settings: settings)
        XCTAssertEqual(ServiceConfiguration.value(key, environment: [:], settings: settings), "https://settings.example/chat")
        XCTAssertEqual(ServiceConfiguration.value(key, environment: [key.environmentName: "https://env.example/chat"], settings: settings), "https://env.example/chat")
        XCTAssertEqual(key.environmentName, "VOX_OPENROUTER_CHAT_URL")
        XCTAssertEqual(ServiceConfiguration.Key.miniUSDPerMinute.environmentName, "VOX_MINI_USD_PER_MINUTE")
    }

    func testInvalidSettingsSaveIsAtomicAndBlankRestoresDefaults() throws {
        let name = "vox-config-test-\(UUID())"
        let settings = UserDefaults(suiteName: name)!
        defer { settings.removePersistentDomain(forName: name) }
        let key = ServiceConfiguration.Key.openaiChatURL
        try ServiceConfiguration.save([key: "https://saved.example/chat"], settings: settings)
        XCTAssertThrowsError(try ServiceConfiguration.save([key: "https://new.example/chat", .cleanupTimeout: "NaN"], settings: settings))
        XCTAssertEqual(settings.string(forKey: key.settingsName), "https://saved.example/chat")
        try ServiceConfiguration.save([key: ""], settings: settings)
        XCTAssertNil(settings.string(forKey: key.settingsName))
    }

    func testInvalidOverridesAreRejectedWithoutProviderFallback() {
        for url in ["http://example.com/chat", "not-a-url", "https://user:password@example.com/chat", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try ServiceConfiguration.validate(url, for: .openaiChatURL))
        }
        for number in ["0", "-1", "NaN", "inf", "1e99"] {
            XCTAssertThrowsError(try ServiceConfiguration.validate(number, for: .cleanupTimeout))
        }
        XCTAssertThrowsError(try ServiceConfiguration.validate("1.2", for: .requestMaxAttempts))
        XCTAssertThrowsError(try ServiceConfiguration.validate("1,,3", for: .meetingRetryDelays))
    }
}
