import XCTest
@testable import vox
@testable import VoxCore

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

    func testAndConnectorRequiresPriorScale() {
        // "and" between non-scale number words must NOT collapse — these are
        // distinct quantities, not a compound number.
        XCTAssertEqual(n.normalize("two and three apples"), "two and three apples")
    }

    func testAndConnectorAfterScaleStillCollapses() {
        XCTAssertEqual(n.normalize("one thousand and twenty"), "1020")
    }

    func testAggressiveConvertsBareSingle() {
        XCTAssertEqual(n.normalize("head -n three", aggressive: true), "head -n 3")
    }

    func testAggressiveStillKeepsNonNumberWords() {
        XCTAssertEqual(n.normalize("apples three pears", aggressive: true), "apples 3 pears")
    }

    func testProseModeUnchangedWithoutAggressive() {
        XCTAssertEqual(n.normalize("I have three apples"), "I have three apples")
    }

    // MARK: - Context-aware prose (currency / time / measurements)

    func testCurrencyDollarsToSymbol() {
        XCTAssertEqual(n.normalize("five dollars"), "$5")
        XCTAssertEqual(n.normalize("costs five dollars today"), "costs $5 today")
        XCTAssertEqual(n.normalize("twenty three dollars"), "$23")
    }

    func testCurrencyCentsToSymbol() {
        XCTAssertEqual(n.normalize("fifty cents"), "50¢")
        XCTAssertEqual(n.normalize("five cents"), "5¢")
    }

    func testCurrencyEuros() {
        XCTAssertEqual(n.normalize("nine euros"), "€9")
    }

    func testTimeHoursToDigits() {
        XCTAssertEqual(n.normalize("three hours"), "3 hours")
        XCTAssertEqual(n.normalize("wait five minutes"), "wait 5 minutes")
    }

    func testLetterSpelledMeasurementNumberToDigits() {
        XCTAssertEqual(n.normalize("F-I-F-T-Y feet"), "50 feet")
    }

    func testOptionNumberUsesDigits() {
        XCTAssertEqual(n.normalize("option one, option two, or option three"), "option 1, option 2, or option 3")
        XCTAssertEqual(n.normalize("Option three is selected"), "Option 3 is selected")
    }

    func testTimeOClock() {
        XCTAssertEqual(n.normalize("meet at five o'clock"), "meet at 5 o'clock")
    }

    func testTimeMeridiem() {
        XCTAssertEqual(n.normalize("leave at nine a.m."), "leave at 9 a.m.")
        XCTAssertEqual(n.normalize("done by five pm"), "done by 5 pm")
    }

    func testDataSizeAbbreviation() {
        XCTAssertEqual(n.normalize("one terabyte"), "1 TB")
        XCTAssertEqual(n.normalize("two gigabytes of ram"), "2 GB of ram")
        XCTAssertEqual(n.normalize("five megabytes"), "5 MB")
    }

    func testPercent() {
        XCTAssertEqual(n.normalize("five percent"), "5%")
    }

    func testOrdinaryProseStillSpellsSmallNumbers() {
        XCTAssertEqual(n.normalize("I have three apples"), "I have three apples")
        XCTAssertEqual(n.normalize("one more thing"), "one more thing")
    }
}
