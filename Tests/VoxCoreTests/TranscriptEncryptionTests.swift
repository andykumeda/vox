import Foundation
import XCTest
@testable import VoxCore

final class TranscriptEncryptionTests: XCTestCase {
    func testRoundTripUsesAuthenticatedEnvelope() throws {
        let cipher = try TranscriptCipher(keyData: Data(repeating: 0x11, count: 32))
        let plaintext = Data("private transcript".utf8)
        let encrypted = try cipher.seal(plaintext)

        XCTAssertTrue(TranscriptCipher.isEncryptedEnvelope(encrypted))
        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertEqual(try cipher.open(encrypted), plaintext)
    }

    func testWrongKeyFailsAuthentication() throws {
        let writer = try TranscriptCipher(keyData: Data(repeating: 0x11, count: 32))
        let reader = try TranscriptCipher(keyData: Data(repeating: 0x22, count: 32))
        let encrypted = try writer.seal(Data("private transcript".utf8))

        XCTAssertThrowsError(try reader.open(encrypted)) { error in
            XCTAssertEqual(error as? TranscriptEncryptionError, .authenticationFailed)
        }
    }

    func testRejectsInvalidKeyAndPlaintextEnvelope() {
        XCTAssertThrowsError(try TranscriptCipher(keyData: Data(repeating: 0, count: 31)))
        XCTAssertThrowsError(
            try TranscriptCipher(keyData: Data(repeating: 0, count: 32))
                .open(Data("plaintext".utf8))
        )
    }
}
