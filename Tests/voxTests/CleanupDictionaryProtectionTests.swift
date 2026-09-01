import XCTest
@testable import vox
@testable import VoxCore

final class CleanupDictionaryProtectionTests: XCTestCase {
    private func entry(
        _ spoken: String,
        _ replacement: String,
        mode: Scope = .prose
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: "test-\(UUID().uuidString)",
            spoken: spoken,
            replacement: replacement,
            mode: mode
        )
    }

    func testFinalProseDictionaryProtectionCorrectsCleanupDrift() {
        let result = CleanupDictionaryProtection.apply(
            "I just saw Leonard.",
            mode: .prose,
            entries: [entry("Leonard", "Lenard")]
        )

        XCTAssertEqual(result, "I just saw Lenard.")
    }

    func testFinalProseDictionaryProtectionLeavesCorrectReplacement() {
        let result = CleanupDictionaryProtection.apply(
            "I just saw Lenard.",
            mode: .prose,
            entries: [entry("Leonard", "Lenard")]
        )

        XCTAssertEqual(result, "I just saw Lenard.")
    }

    func testFinalDictionaryProtectionSkipsCommandMode() {
        let result = CleanupDictionaryProtection.apply(
            "echo Leonard",
            mode: .command,
            entries: [entry("Leonard", "Lenard", mode: .both)]
        )

        XCTAssertEqual(result, "echo Leonard")
    }

    func testFinalDictionaryProtectionPreservesNewlineTriggerOutput() {
        let result = CleanupDictionaryProtection.apply(
            "Hi Leonard.\nTalk tomorrow.",
            mode: .prose,
            entries: [entry("Leonard", "Lenard")]
        )

        XCTAssertEqual(result, "Hi Leonard.\nTalk tomorrow.")
    }
}
