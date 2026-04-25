import XCTest
@testable import vox

final class NumberNormalizerTests: XCTestCase {
    let n = NumberNormalizer()

    func testSingleSmallNumberStaysAsWord() {
        // Spelled-out 1–9 in prose reads better as a word.
        XCTAssertEqual(n.normalize("I have three apples"), "I have three apples")
    }

    func testSingleTenOrAboveConverts() {
        XCTAssertEqual(n.normalize("I have twenty apples"), "I have 20 apples")
    }

    func testTeens() {
        XCTAssertEqual(n.normalize("age fifteen today"), "age 15 today")
    }

    func testCompoundTens() {
        XCTAssertEqual(n.normalize("I have twenty three apples"), "I have 23 apples")
    }

    func testHyphenatedCompound() {
        XCTAssertEqual(n.normalize("twenty-three apples"), "23 apples")
    }

    func testHundreds() {
        XCTAssertEqual(n.normalize("one hundred twenty three"), "123")
    }

    func testThousands() {
        XCTAssertEqual(n.normalize("two thousand five hundred"), "2500")
    }

    func testAndConnector() {
        XCTAssertEqual(n.normalize("two hundred and fifty"), "250")
    }

    func testNoNumbers() {
        XCTAssertEqual(n.normalize("hello world"), "hello world")
    }

    func testPreservesSurroundingPunctuation() {
        // Single-digit words left as words, but multi-word runs still convert.
        XCTAssertEqual(n.normalize("bought three. sold twenty."), "bought three. sold 20.")
    }

    func testLeadingSmallNumberWordStays() {
        XCTAssertEqual(n.normalize("five apples"), "five apples")
    }

    func testTrailingSmallNumberWordStays() {
        XCTAssertEqual(n.normalize("apples five"), "apples five")
    }
}
