import XCTest
@testable import vox

final class DictationRegressionTests: XCTestCase {
    private let latencyBudgetMs: Double = 50.0
    private let failureRateBudget: Double = 0.0
    private let qualityFloor: Double = 0.98

    func testDictationRegressionBudgets() {
        let fixtures = DictationRegressionFixture.all
        XCTAssertFalse(fixtures.isEmpty)

        let prose = PostProcessor(mode: .prose)
        let command = PostProcessor(mode: .command)

        let clock = ContinuousClock()
        let start = clock.now

        var failures = 0
        var exactMatches = 0

        for fixture in fixtures {
            let processor = fixture.mode == .prose ? prose : command
            let output = processor.apply(fixture.input)
            if output != fixture.expected {
                failures += 1
            } else {
                exactMatches += 1
            }
        }

        let end = clock.now
        let elapsed = start.duration(to: end)
        let latencyMs = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0

        let total = Double(fixtures.count)
        let failureRate = Double(failures) / total
        let qualityScore = Double(exactMatches) / total

        print("Dictation baseline metrics: fixtures=\(fixtures.count) latency_ms=\(latencyMs) failure_rate=\(failureRate) quality_score=\(qualityScore)")

        XCTAssertLessThanOrEqual(
            latencyMs,
            latencyBudgetMs,
            "Dictation latency regression: \(latencyMs)ms > budget \(latencyBudgetMs)ms"
        )
        XCTAssertLessThanOrEqual(
            failureRate,
            failureRateBudget,
            "Dictation failure-rate regression: \(failureRate) > budget \(failureRateBudget)"
        )
        XCTAssertGreaterThanOrEqual(
            qualityScore,
            qualityFloor,
            "Dictation quality regression: \(qualityScore) < floor \(qualityFloor)"
        )
    }
}

private struct DictationRegressionFixture {
    let mode: TranscriptionMode
    let input: String
    let expected: String

    static let all: [DictationRegressionFixture] = [
        .init(mode: .prose, input: "hello world", expected: "Hello world."),
        .init(mode: .prose, input: "is it raining", expected: "Is it raining?"),
        .init(mode: .prose, input: "check out youtube.com", expected: "Check out youtube.com."),
        .init(mode: .command, input: "Sudo apt update", expected: "sudo apt update"),
        .init(mode: .command, input: "head dash n three", expected: "head -n 3"),
        .init(mode: .command, input: "ls pipe grep foo", expected: "ls | grep foo"),
        .init(mode: .command, input: "cat readme dot md", expected: "cat readme.md"),
            ]
}
