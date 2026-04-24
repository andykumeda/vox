import XCTest
@testable import vox

final class NumberNormalizerTests: XCTestCase {
    let n = NumberNormalizer()

    func testSingleDigit() {
        XCTAssertEqual(n.normalize("I have three apples"), "I have 3 apples")
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
        XCTAssertEqual(n.normalize("bought three. sold five."), "bought 3. sold 5.")
    }

    func testLeadingNumberWord() {
        XCTAssertEqual(n.normalize("five apples"), "5 apples")
    }

    func testTrailingNumberWord() {
        XCTAssertEqual(n.normalize("apples five"), "apples 5")
    }
}
