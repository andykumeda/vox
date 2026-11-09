import AppKit
import SwiftUI

/// Floating panel near the menu bar that shows meeting recording controls.
/// Visible state is controlled by the user (hotkey or menu); the session
/// itself is started/stopped only when the user clicks Record/Stop in the
/// panel.
@MainActor
public final class MeetingHUDPanel: NSObject, NSWindowDelegate {
    public static let shared = MeetingHUDPanel()

    private var panel: NSPanel?

    private static let positionKey = "meetingHUDPosition"

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    /// Toggle panel visibility. If the meeting session is recording when
    /// the panel is hidden, the recording continues — the panel is purely
    /// a UI surface, not the session lifecycle.
    public func toggle() {
        if let panel, panel.isVisible && !panel.isMiniaturized {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        if let panel {
            if panel.isMiniaturized { panel.deminiaturize(nil) }
            keepOnScreen(panel)
            panel.orderFrontRegardless()
            return
        }

        let view = MeetingHUDView(
            onStart: {
                Task { @MainActor in
                    do {
                        try await MeetingTranscriptionSession.shared.start()
                    } catch {
                        dlog("Meeting start failed: \(error)")
                        let alert = NSAlert()
                        alert.messageText = "Meeting Transcription"
                        alert.informativeText = String(describing: error)
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            },
            onStop: {
                Task { @MainActor in
                    do {
                        try await MeetingTranscriptionSession.shared.stop()
                    } catch {
                        dlog("Meeting stop failed: \(error)")
                    }
                    // Auto-open the transcript browser so the user can read
                    // the just-finished meeting without an extra step.
                    MeetingTranscriptsWindow.shared.show()
                }
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 270, height: 54)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Meeting"
        p.isReleasedWhenClosed = false
        p.contentMinSize = hosting.frame.size
        p.tabbingMode = .disallowed
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        // Follow the user across Spaces and into full-screen apps so the
        // recording controls stay reachable no matter which desktop is active.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = hosting
        p.delegate = self
        let saved = UserDefaults.standard.array(forKey: Self.positionKey) as? [Double]
        if let saved, saved.count == 2, saved.allSatisfy({ $0.isFinite }) {
            p.setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
        } else if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - p.frame.width - 12,
                y: screen.visibleFrame.maxY - p.frame.height - 12
            ))
        }
        keepOnScreen(p)
        p.orderFrontRegardless()
        self.panel = p
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    public func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        UserDefaults.standard.set(
            [Double(panel.frame.minX), Double(panel.frame.minY)], forKey: Self.positionKey
        )
    }

    @objc private func screensChanged() {
        if let panel { keepOnScreen(panel) }
    }

    private func keepOnScreen(_ panel: NSPanel) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        panel.setFrameOrigin(Self.visibleOrigin(for: panel.frame, screens: screens))
    }

    nonisolated static func visibleOrigin(for frame: NSRect, screens: [NSRect]) -> NSPoint {
        guard let screen = screens.max(by: {
            let a = $0.intersection(frame)
            let b = $1.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }) else { return frame.origin }
        return NSPoint(
            x: min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width)),
            y: min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height))
        )
    }
}

@MainActor
struct MeetingHUDView: View {
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        // TimelineView re-evaluates its content every 0.5s, which re-reads
        // the session state and the elapsed timer. Plain Timer.publish did
        // not fire inside the NSPanel hosting context.
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            content(now: ctx.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let isRecording = MeetingTranscriptionSession.shared.isRecording
        let isActive    = MeetingTranscriptionSession.shared.isActive
        let startedAt: Date? = {
            guard let id = MeetingTranscriptionSession.shared.activeSessionID else { return nil }
            return MeetingTranscriptionSession.shared.store.load(id: id)?.startedAt
        }()

        HStack(spacing: 12) {
            Button(action: onStart) {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.45) : Color.green)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isActive)
            .accessibilityLabel("Start recording")
            .help(isActive ? "Already recording" : "Start recording")

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isRecording ? Color.red : Color.red.opacity(0.45))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!isRecording)
            .accessibilityLabel("Stop recording")
            .help(isRecording ? "Stop recording" : "Not recording")

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                Text(statusLabel(isActive: isActive))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(elapsed(now: now, start: startedAt, isActive: isActive))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusLabel(isActive: Bool) -> String {
        switch MeetingTranscriptionSession.shared.statusSnapshot {
        case .recording:    return "Recording"
        case .chunking:     return "Chunking…"
        case .transcribing:
            if let id = MeetingTranscriptionSession.shared.activeSessionID,
               let s = MeetingTranscriptionSession.shared.store.load(id: id) {
                return "Transcribing \(s.chunksCompleted)/\(s.chunksTotal)"
            }
            return "Transcribing…"
        case .completed:    return "Last meeting saved"
        case .cancelled:    return "Last meeting cancelled"
        case .failed:       return "Last meeting failed"
        case .none:         return "Ready to record"
        }
    }

    private func elapsed(now: Date, start: Date?, isActive: Bool) -> String {
        // Count up live only while still recording. Once stop() sets
        // endedAt (status flips to .chunking), freeze the timer — the user
        // wants the final recorded duration, not chunk+transcribe time.
        let session: TranscriptSession? = {
            guard let id = MeetingTranscriptionSession.shared.activeSessionID else { return nil }
            return MeetingTranscriptionSession.shared.store.load(id: id)
        }()
        let referenceStart = start ?? session?.startedAt
        let referenceEnd: Date? = session?.endedAt ?? (isActive ? now : nil)
        guard let s = referenceStart, let e = referenceEnd else { return "--:--" }
        let secs = max(0, Int(e.timeIntervalSince(s)))
        let m = secs / 60, ss = secs % 60
        if secs >= 3600 {
            let h = secs / 3600, mm = (secs % 3600) / 60
            return String(format: "%d:%02d:%02d", h, mm, ss)
        }
        return String(format: "%02d:%02d", m, ss)
    }
}
