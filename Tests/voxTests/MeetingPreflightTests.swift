import XCTest
@testable import vox

final class MeetingPreflightTests: XCTestCase {
    private var savedProvider: (@Sendable (MeetingCaptureBackend) -> MeetingBackendStatus)!

    override func setUp() {
        super.setUp()
        savedProvider = MeetingPreflight.backendStatusProvider
    }

    override func tearDown() {
        MeetingPreflight.backendStatusProvider = savedProvider
        super.tearDown()
    }

    private func assertFailure(
        _ result: Result<Void, MeetingGateError>,
        equals expected: MeetingGateError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("expected failure \(expected) but got success", file: file, line: line)
        case .failure(let err):
            XCTAssertEqual(err, expected, file: file, line: line)
        }
    }

    func testGateDeniesWhenModeDisabled() {
        let result = MeetingPreflight.gate(
            modeEnabled: false,
            consentAcknowledged: true,
            backend: .systemAudio,
            hasAPIKey: true
        )
        assertFailure(result, equals: .modeDisabled)
    }

    func testGateDeniesWhenConsentMissing() {
        let result = MeetingPreflight.gate(
            modeEnabled: true,
            consentAcknowledged: false,
            backend: .systemAudio,
            hasAPIKey: true
        )
        assertFailure(result, equals: .consentRequired)
    }

    func testGateDeniesWhenAPIKeyMissing() {
        let result = MeetingPreflight.gate(
            modeEnabled: true,
            consentAcknowledged: true,
            backend: .systemAudio,
            hasAPIKey: false
        )
        assertFailure(result, equals: .missingAPIKey)
    }

    func testGateDeniesWhenBackendUnavailable() {
        MeetingPreflight.backendStatusProvider = { _ in
            MeetingBackendStatus(available: false, detail: "missing entitlement")
        }
        let result = MeetingPreflight.gate(
            modeEnabled: true,
            consentAcknowledged: true,
            backend: .systemAudio,
            hasAPIKey: true
        )
        assertFailure(result, equals: .backendUnavailable(reason: "missing entitlement"))
    }

    func testGatePassesWhenAllCriteriaMet() {
        MeetingPreflight.backendStatusProvider = { _ in
            MeetingBackendStatus(available: true, detail: "ready")
        }
        let result = MeetingPreflight.gate(
            modeEnabled: true,
            consentAcknowledged: true,
            backend: .systemAudio,
            hasAPIKey: true
        )
        switch result {
        case .success: break
        case .failure(let err): XCTFail("expected success, got \(err)")
        }
    }

    func testDefaultBackendStatusIsPendingImplementation() {
        let status = MeetingBackendStatus.pendingImplementation
        XCTAssertFalse(status.available)
        XCTAssertTrue(status.detail.contains("M2"))
    }
}
