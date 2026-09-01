import Foundation
import XCTest
@testable import VoxCore

final class MobileDictationExchangeTests: XCTestCase {
    func testActiveRequestCannotBeReplaced() throws {
        let first = try store.beginRequest()

        XCTAssertThrowsError(try store.beginRequest()) { error in
            XCTAssertEqual(error as? MobileDictationExchangeError, .requestInProgress)
        }

        _ = try store.transition(requestID: try XCTUnwrap(first.requestID), to: .cancelled)
        XCTAssertNoThrow(try store.beginRequest())
    }

    private var temporaryDirectory: URL!
    private var store: MobileDictationExchangeStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = MobileDictationExchangeStore(
            fileURL: temporaryDirectory.appendingPathComponent("exchange.json")
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRequestCanProgressToOneConsumableResult() throws {
        let requestID = UUID()
        let started = try store.beginRequest(
            now: Date(timeIntervalSince1970: 10),
            requestID: requestID
        )
        XCTAssertEqual(started.phase, .requestingHandoff)

        _ = try store.transition(requestID: requestID, to: .recording)
        _ = try store.transition(requestID: requestID, to: .stopRequested)
        _ = try store.transition(requestID: requestID, to: .transcribing)
        _ = try store.transition(requestID: requestID, to: .ready, resultText: "Hello world.")

        XCTAssertEqual(try store.consumeReadyResult(requestID: requestID), "Hello world.")
        XCTAssertNil(try store.consumeReadyResult(requestID: requestID))
        XCTAssertEqual(try store.load().phase, .consumed)
    }

    func testStaleRequestCannotTransitionOrConsumeCurrentResult() throws {
        let currentRequestID = UUID()
        _ = try store.beginRequest(requestID: currentRequestID)

        XCTAssertThrowsError(
            try store.transition(requestID: UUID(), to: .recording)
        ) { error in
            XCTAssertEqual(error as? MobileDictationExchangeError, .requestMismatch)
        }
        XCTAssertThrowsError(
            try store.consumeReadyResult(requestID: UUID())
        ) { error in
            XCTAssertEqual(error as? MobileDictationExchangeError, .requestMismatch)
        }
    }

    func testInvalidTransitionAndMissingReadyResultAreRejected() throws {
        let requestID = UUID()
        _ = try store.beginRequest(requestID: requestID)

        XCTAssertThrowsError(
            try store.transition(requestID: requestID, to: .ready, resultText: "Too soon")
        ) { error in
            XCTAssertEqual(
                error as? MobileDictationExchangeError,
                .invalidTransition(from: .requestingHandoff, to: .ready)
            )
        }

        _ = try store.transition(requestID: requestID, to: .recording)
        _ = try store.transition(requestID: requestID, to: .stopRequested)
        _ = try store.transition(requestID: requestID, to: .transcribing)
        XCTAssertThrowsError(
            try store.transition(requestID: requestID, to: .ready)
        ) { error in
            XCTAssertEqual(error as? MobileDictationExchangeError, .missingResult)
        }
    }

    func testPersistenceRoundTripsDatesUsingStableSchema() throws {
        let requestID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try store.beginRequest(now: date, requestID: requestID)

        let loaded = try store.load()
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.requestID, requestID)
        XCTAssertEqual(loaded.createdAt, date)
        XCTAssertEqual(loaded.updatedAt, date)
    }
}
