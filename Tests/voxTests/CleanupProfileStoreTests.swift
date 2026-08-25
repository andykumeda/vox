import XCTest
@testable import vox

final class CleanupProfileStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-cleanup-profile-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testInitCreatesSupportDirectory() {
        let fileURL = tempDir
            .appendingPathComponent("Nested", isDirectory: true)
            .appendingPathComponent("cleanup-profile.md")

        _ = CleanupProfileStore(fileURL: fileURL)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fileURL.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testMissingFileReturnsEmptyString() {
        let store = CleanupProfileStore(
            fileURL: tempDir.appendingPathComponent("cleanup-profile.md")
        )

        XCTAssertEqual(store.load(), "")
    }

    func testSaveLoadRoundTrip() throws {
        let store = CleanupProfileStore(
            fileURL: tempDir.appendingPathComponent("cleanup-profile.md")
        )

        try store.save("Prefer minimal edits.\nKeep my casual wording.")

        XCTAssertEqual(store.load(), "Prefer minimal edits.\nKeep my casual wording.")
    }

    func testResetClearsSavedProfile() throws {
        let store = CleanupProfileStore(
            fileURL: tempDir.appendingPathComponent("cleanup-profile.md")
        )
        try store.save("Do not rewrite my phrasing.")

        try store.reset()

        XCTAssertEqual(store.load(), "")
    }

    func testExtractsAdditionalCorrectionTriggers() {
        let profile = "Additional trigger: “rather”, “or rather” - should function like “scratch that”\n"

        XCTAssertEqual(
            CleanupProfileStore.additionalScratchThatTriggers(from: profile),
            ["rather", "or rather"]
        )
    }

    func testDoesNotTreatOrdinaryProfileTextAsTrigger() {
        XCTAssertEqual(
            CleanupProfileStore.additionalScratchThatTriggers(from: "Preserve my casual phrasing."),
            []
        )
    }
}
