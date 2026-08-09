import AppKit
import CoreGraphics
import Foundation

/// Pollable meeting auto-detector. Watches running apps + their on-screen
/// window titles, fires `onMeetingStarted` when a known meeting app shows
/// a meeting-pattern window. Fires `onMeetingEnded` when no meeting signal
/// has been seen for several consecutive polls (hysteresis prevents
/// flicker during window switches).
///
/// Detection is title-based and heuristic. False positives are tolerable
/// because the only consequence is the floating Meeting panel showing —
/// the user still has to click Record. Auto-recording is intentionally
/// not provided here; consent flow stays on the panel.
///
/// The detector must be created and driven from the main thread — the
/// timer fires on `RunLoop.main` and all Cocoa window-info APIs require
/// the main thread.
public final class MeetingDetector {
    public typealias Callback = () -> Void

    public var onMeetingStarted: Callback?
    public var onMeetingEnded: Callback?

    private var timer: Timer?
    private var inMeeting: Bool = false
    private var missCount: Int = 0

    static let pollSeconds: TimeInterval = 3
    /// Consecutive misses before we flip from in-meeting → not. At
    /// `pollSeconds = 3` and 3 misses, that's ~9s of clean signal before
    /// we conclude the meeting really ended.
    static let endHysteresisPolls: Int = 3

    public init() {}

    public func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        inMeeting = false
        missCount = 0
    }

    public var isInMeeting: Bool { inMeeting }

    private func tick() {
        let runningApps = NSWorkspace.shared.runningApplications
        let frontmostOwner = NSWorkspace.shared.frontmostApplication?.localizedName

        // CGWindowListCopyWindowInfo crosses into WindowServer and is much more
        // expensive than inspecting the frontmost application. When auto-show is
        // enabled, do not query every on-screen window on every poll while the user
        // is working in an unrelated app. Keep polling after a match so a meeting
        // can still end cleanly when the user switches apps.
        guard Self.shouldInspectWindows(
            frontmostOwner: frontmostOwner,
            inMeeting: inMeeting
        ) else {
            return
        }

        let windows = Self.snapshotWindows()
        let match = Self.firstMatchingWindow(runningApps: runningApps, windows: windows)
        let active = (match != nil)

        // Diagnostic logging. The empty-title case is the most common false
        // negative — Vox.app needs Screen Recording permission for
        // CGWindowListCopyWindowInfo to populate window titles.
        if windows.allSatisfy({ $0.title.isEmpty }) && !windows.isEmpty {
            dlog("MeetingDetector: \(windows.count) windows, all titles empty (Screen Recording permission missing?)")
        }

        if active, let m = match {
            missCount = 0
            if !inMeeting {
                inMeeting = true
                dlog("MeetingDetector: started — owner=\"\(m.owner)\" windows=\(windows.count) matched_title_chars=\(m.title.count)")
                onMeetingStarted?()
            }
        } else if inMeeting {
            missCount += 1
            if missCount >= Self.endHysteresisPolls {
                inMeeting = false
                missCount = 0
                dlog("MeetingDetector: ended (hysteresis cleared)")
                onMeetingEnded?()
            }
        }
    }

    // MARK: - Window snapshot

    static func shouldInspectWindows(frontmostOwner: String?, inMeeting: Bool) -> Bool {
        guard !inMeeting else { return true }
        guard let frontmostOwner else { return false }
        return meetingApps.contains(frontmostOwner) || browserApps.contains(frontmostOwner)
    }

    /// (ownerName, windowTitle) for every on-screen regular window.
    static func snapshotWindows() -> [(owner: String, title: String)] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let owner = dict[kCGWindowOwnerName as String] as? String else { return nil }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            return (owner, title)
        }
    }

    // MARK: - Pure detection logic

    /// Desktop meeting apps. Match against `kCGWindowOwnerName`.
    static let meetingApps: Set<String> = [
        "Microsoft Teams",
        "Microsoft Teams (work or school)",
        "Microsoft Teams classic",
        "zoom.us",
        "Zoom",
        "Webex",
        "Cisco Webex",
        "Cisco Webex Meetings",
        "Slack",
        "Discord",
        "Skype",
        "Google Meet",
    ]

    /// Browser apps. Their on-screen window title is the focused tab's
    /// title — sufficient for detecting a Meet/Teams/Zoom tab as long as
    /// it's the active tab. Background tabs are invisible to us.
    static let browserApps: Set<String> = [
        "Google Chrome",
        "Chrome",
        "Safari",
        "Microsoft Edge",
        "Arc",
        "Brave Browser",
        "Firefox",
    ]

    /// Substrings that indicate an in-progress meeting inside a known
    /// desktop meeting-app window. Substring match is case-sensitive.
    static let desktopMeetingPatterns: [String] = [
        // Teams (channel meetings, 1:1 calls, compact-view, plus the
        // explicit "(Meeting)" tag the new client sometimes uses)
        "Meeting in",
        "Meeting with",
        "Meeting compact view",
        "Call with",
        "(Meeting)",
        // Zoom
        "Zoom Meeting",
        "Zoom Webinar",
        // Webex
        "Webex Meeting",
        "Webex Personal Room",
        // Slack
        "Huddle",
        // Discord / Skype
        "Voice Call",
        "Video Call",
        "Skype Call",
    ]

    /// Substrings that indicate an in-progress meeting inside a browser
    /// tab title. Be conservative: bare product names like "Microsoft
    /// Teams" appear in every chat tab, not just meetings — patterns must
    /// be specific enough that a non-meeting tab doesn't match.
    static let browserMeetingPatterns: [String] = [
        // Google Meet (`<title> - Google Meet` and `meet.google.com`)
        "Google Meet",
        "meet.google.com",
        // Zoom web
        "Zoom Meeting",
        // Webex web
        "Webex Meeting",
        // Teams web meeting URL pattern (avoid bare "Microsoft Teams" which
        // matches every Teams chat tab).
        "/_#/meetingjoin/",
        "/l/meetup-join/",
    ]

    static func detectActiveMeeting(
        runningApps: [NSRunningApplication],
        windows: [(owner: String, title: String)]
    ) -> Bool {
        firstMatchingWindow(runningApps: runningApps, windows: windows) != nil
    }

    /// Returns the first window whose owner is a known meeting app and
    /// whose title matches a meeting pattern, or nil. Window titles may
    /// contain sensitive meeting details and must not be written to logs.
    static func firstMatchingWindow(
        runningApps: [NSRunningApplication],
        windows: [(owner: String, title: String)]
    ) -> (owner: String, title: String)? {
        let runningNames = Set(runningApps.compactMap { $0.localizedName })
        for window in windows {
            if meetingApps.contains(window.owner), runningNames.contains(window.owner) {
                if matchesAny(window.title, patterns: desktopMeetingPatterns) {
                    return window
                }
            }
            if browserApps.contains(window.owner), runningNames.contains(window.owner) {
                if matchesAny(window.title, patterns: browserMeetingPatterns) {
                    return window
                }
            }
        }
        return nil
    }

    static func matchesAny(_ s: String, patterns: [String]) -> Bool {
        patterns.contains { s.contains($0) }
    }
}
