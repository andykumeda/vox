import XCTest
@testable import vox

final class MeetingDetectorTests: XCTestCase {

    private struct StubApp {
        let name: String
    }

    private func runningWith(_ names: [String]) -> [NSRunningApplication] {
        // We can't construct NSRunningApplication; tests directly call the
        // pure detection function with a custom shape. Detector accepts
        // [NSRunningApplication], so we exercise pattern-matching via the
        // helper `matchesAny` and the pattern lists themselves.
        return []
    }

    // MARK: - matchesAny

    func testMatchesAnyHitsSingleSubstring() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "Meeting in Marketing Channel | Microsoft Teams",
            patterns: ["Meeting in"]
        ))
    }

    func testMatchesAnyMissesUnrelatedTitle() {
        XCTAssertFalse(MeetingDetector.matchesAny(
            "Inbox - Outlook",
            patterns: MeetingDetector.desktopMeetingPatterns
        ))
    }

    func testMatchesAnyHitsZoomMeeting() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "Zoom Meeting",
            patterns: MeetingDetector.desktopMeetingPatterns
        ))
    }

    func testMatchesAnyHitsSlackHuddle() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "Huddle in #design",
            patterns: MeetingDetector.desktopMeetingPatterns
        ))
    }

    func testMatchesAnyMissesSlackChannelWithoutHuddle() {
        XCTAssertFalse(MeetingDetector.matchesAny(
            "Slack | #design",
            patterns: MeetingDetector.desktopMeetingPatterns
        ))
    }

    // MARK: - Browser patterns

    func testMatchesAnyHitsGoogleMeetTab() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "Vox demo - Google Meet",
            patterns: MeetingDetector.browserMeetingPatterns
        ))
    }

    func testMatchesAnyHitsMeetGoogleDotComUrl() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "meet.google.com/abc-defg-hij",
            patterns: MeetingDetector.browserMeetingPatterns
        ))
    }

    func testMatchesAnyHitsZoomWebMeeting() {
        XCTAssertTrue(MeetingDetector.matchesAny(
            "Zoom Meeting - Google Chrome",
            patterns: MeetingDetector.browserMeetingPatterns
        ))
    }

    func testMatchesAnyMissesGenericBrowserTab() {
        XCTAssertFalse(MeetingDetector.matchesAny(
            "Hacker News - Google Chrome",
            patterns: MeetingDetector.browserMeetingPatterns
        ))
    }

    // MARK: - Pattern coverage

    func testDesktopPatternsCoverKnownProducts() {
        // Sanity check that we ship patterns for each product the docs claim.
        let mustMatch: [(String, String)] = [
            ("Meeting in Standup | Microsoft Teams", "Teams desktop channel meeting"),
            ("Meeting compact view | Meeting with Kumeda, Andy | Microsoft Teams",
             "Teams desktop 1:1 compact view (real-world title from 0.6.4 testing)"),
            ("Zoom Meeting", "Zoom desktop"),
            ("Webex Meeting - Project sync", "Webex desktop"),
            ("Huddle", "Slack huddle"),
            ("Voice Call - John Smith", "Discord voice"),
        ]
        for (title, label) in mustMatch {
            XCTAssertTrue(
                MeetingDetector.matchesAny(title, patterns: MeetingDetector.desktopMeetingPatterns),
                "\(label): \(title)"
            )
        }
    }
}
