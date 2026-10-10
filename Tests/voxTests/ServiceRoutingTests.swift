import XCTest
@testable import vox
@testable import VoxCore

final class ServiceRoutingTests: XCTestCase {
    func testCleanupAndSummaryFollowCurrentDictationUnlessExplicitlyOverridden() {
        let defaults = UserDefaults.standard
        let keys = ["dictationProvider", "cleanupProvider", "summaryProvider"]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) } }
        defaults.removeObject(forKey: "cleanupProvider")
        defaults.removeObject(forKey: "summaryProvider")
        AppSettings.dictationProvider = .openrouter
        XCTAssertEqual(AppSettings.cleanupProvider, .openrouter)
        XCTAssertEqual(AppSettings.summaryProvider, .openrouter)
        AppSettings.dictationProvider = .openai
        XCTAssertEqual(AppSettings.cleanupProvider, .openai)
        defaults.set("openrouter", forKey: "cleanupProvider")
        XCTAssertEqual(AppSettings.cleanupProvider, .openrouter)
        XCTAssertEqual(AppSettings.summaryProvider, .openai)
    }

    func testOpenRouterCleanupUsesRouterEndpointModelAndCredential() async throws {
        var calls = 0
        let cleaner = makeLiveLLMCleaner(
            apiKeyProvider: { "router-test-key" },
            configurationProvider: { try .resolve(provider: .openrouter) },
            send: { request in
                calls += 1
                XCTAssertEqual(request.url, try ServiceConfiguration.url(.openrouterChatURL))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-test-key")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(body["model"] as? String, try ServiceConfiguration.string(.openrouterCleanupModel))
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"choices":[{"message":{"content":"Test output."}}]}"#.utf8), response)
            }
        )
        let output = try await cleaner("Synthetic test input.")
        XCTAssertEqual(output, "Test output.")
        XCTAssertEqual(calls, 1)
    }

    func testOpenRouterSummaryUsesRouterEndpointModelAndCredential() async throws {
        let client = MeetingSummarizer(apiKeyProvider: { "router-test-key" }, provider: .openrouter, send: { request in
            XCTAssertEqual(request.url, try ServiceConfiguration.url(.openrouterChatURL))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-test-key")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, try ServiceConfiguration.string(.openrouterSummaryModel))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"Test summary."}}]}"#.utf8), response)
        })
        let output = try await client.summarize(segments: [.init(startTime: 0, endTime: 1, text: "Synthetic input.", source: .local)])
        XCTAssertEqual(output, "Test summary.")
    }

    func testCleanupHonorsSavedEndpointModelAndRequestBudgets() async throws {
        let defaults = UserDefaults.standard
        let values: [ServiceConfiguration.Key: String] = [
            .openrouterChatURL: "https://custom.example/chat",
            .openrouterCleanupModel: "custom/model", .cleanupTimeout: "17",
            .cleanupMaxTokens: "123", .temperature: "0.2"
        ]
        let old = values.keys.map { ($0, defaults.object(forKey: $0.settingsName)) }
        defer { for (key, value) in old { defaults.set(value, forKey: key.settingsName) } }
        try ServiceConfiguration.save(values)
        let cleaner = makeLiveLLMCleaner(apiKeyProvider: { "test" }, configurationProvider: { try .resolve(provider: .openrouter) }, send: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://custom.example/chat")
            XCTAssertEqual(request.timeoutInterval, 17)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "custom/model")
            XCTAssertEqual(body["max_tokens"] as? Int, 123)
            XCTAssertEqual(body["temperature"] as? Double, 0.2)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"Output."}}]}"#.utf8), response)
        })
        _ = try await cleaner("Synthetic input.")
    }

    func testRouterFailureNeverSendsToOpenAI() async throws {
        var sends = 0
        let cleaner = makeLiveLLMCleaner(apiKeyProvider: { "test" }, configurationProvider: { try .resolve(provider: .openrouter) }, send: { request in
            sends += 1
            XCTAssertEqual(request.url, try ServiceConfiguration.url(.openrouterChatURL))
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
        do { _ = try await cleaner("Synthetic input."); XCTFail("Expected service failure") }
        catch { XCTAssertEqual(sends, 1) }
    }

    func testInvalidProviderDoesNotSilentlyRouteToOpenAI() throws {
        let key = ServiceConfiguration.Key.cleanupProvider.settingsName
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: key)
        defer { defaults.set(old, forKey: key) }
        defaults.set("openroutr", forKey: key)
        XCTAssertThrowsError(try AppSettings.resolvedTextProvider(.cleanupProvider))
    }

    func testUnrepresentableMeetingChunkCountFailsWithoutTrapping() throws {
        XCTAssertThrowsError(try MeetingChunker.chunkCount(totalDuration: 10, chunkDuration: 1e-300))
        XCTAssertEqual(try MeetingChunker.chunkCount(totalDuration: 650, chunkDuration: 300), 3)
    }

    func testBadEndpointOverrideFailsBeforeSending() async throws {
        let key = ServiceConfiguration.Key.openrouterChatURL
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: key.settingsName)
        defer { defaults.set(old, forKey: key.settingsName) }
        defaults.set("invalid", forKey: key.settingsName)
        var sent = false
        let cleaner = makeLiveLLMCleaner(apiKeyProvider: { "test" }, configurationProvider: { try .resolve(provider: .openrouter) }, send: { _ in
            sent = true
            return (Data(), URLResponse())
        })
        do { _ = try await cleaner("Synthetic input."); XCTFail("Expected configuration error") }
        catch is ServiceConfiguration.InvalidValue { }
        XCTAssertFalse(sent)
    }
}
