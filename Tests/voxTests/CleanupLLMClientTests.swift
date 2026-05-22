import XCTest
@testable import vox

final class CleanupLLMClientTests: XCTestCase {
    private func entry(
        _ spoken: String,
        _ replacement: String,
        mode: Scope = .prose,
        enabled: Bool = true
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: "test-\(UUID().uuidString)",
            spoken: spoken,
            replacement: replacement,
            mode: mode,
            enabled: enabled
        )
    }

    func testPromptOmitsEmptyProfileSection() {
        let prompt = makeCleanupSystemPrompt(profile: "   \n  ", dictionaryEntries: [])

        XCTAssertFalse(prompt.contains("Personal cleanup profile from the user"))
    }

    func testPromptIncludesNonEmptyProfile() {
        let prompt = makeCleanupSystemPrompt(
            profile: "Prefer minimal edits.\nKeep my casual wording.",
            dictionaryEntries: []
        )

        XCTAssertTrue(prompt.contains("Personal cleanup profile from the user"))
        XCTAssertTrue(prompt.contains("Prefer minimal edits."))
        XCTAssertTrue(prompt.contains("Keep my casual wording."))
    }

    func testPromptIncludesActiveProseDictionaryEntries() {
        let prompt = makeCleanupSystemPrompt(
            dictionaryEntries: [
                entry("Leonard", "Lenard", mode: .prose),
                entry("superbase", "Supabase", mode: .both),
            ]
        )

        XCTAssertTrue(prompt.contains("\"Leonard\" -> \"Lenard\""))
        XCTAssertTrue(prompt.contains("\"superbase\" -> \"Supabase\""))
    }

    func testPromptExcludesCommandOnlyAndDisabledDictionaryEntries() {
        let prompt = makeCleanupSystemPrompt(
            dictionaryEntries: [
                entry("password", "passwd", mode: .command),
                entry("Micky", "Miki", mode: .prose, enabled: false),
            ]
        )

        XCTAssertFalse(prompt.contains("password"))
        XCTAssertFalse(prompt.contains("passwd"))
        XCTAssertFalse(prompt.contains("Micky"))
        XCTAssertFalse(prompt.contains("Miki"))
        XCTAssertFalse(prompt.contains("User dictionary preservation rules"))
    }
}
