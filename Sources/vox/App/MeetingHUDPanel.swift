import AppKit
import SwiftUI

/// Floating panel near the menu bar that shows meeting recording controls.
/// Visible state is controlled by the user (hotkey or menu); the session
/// itself is started/stopped only when the user clicks Record/Stop in the
/// panel.
@MainActor
public final class MeetingHUDPanel {
    public static let shared = MeetingHUDPanel()

    private var panel: NSPanel?
    private var isVisible = false

    private init() {}

    /// Toggle panel visibility. If the meeting session is recording when
    /// the panel is hidden, the recording continues — the panel is purely
    /// a UI surface, not the session lifecycle.
    public func toggle() {
        if isVisible { hide() } else { show() }
    }

    public func show() {
        if isVisible, let panel = panel {
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
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 270, height: 95)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        // Follow the user across Spaces and into full-screen apps so the
        // recording controls stay reachable no matter which desktop is active.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hosting
        positionNearMenuBar(p)
        p.orderFrontRegardless()
        self.panel = p
        self.isVisible = true
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }

    private func positionNearMenuBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let inset: CGFloat = 12
        let menuBarHeight: CGFloat = 24
        let frame = panel.frame
        let x = screen.frame.maxX - frame.width - inset
        let y = screen.frame.maxY - frame.height - menuBarHeight - inset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
struct MeetingHUDView: View {
    let onStart: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide panel (recording continues if active)")
                    Text("Meeting")
                        .font(.system(size: 13, weight: .semibold))
                }

                HStack(spacing: 12) {
                    // Solid green Record disc. Stays prominently green even
                    // while a recording is in progress (just dimmed slightly
                    // and disabled) so the control's affordance is visible.
                    Button(action: onStart) {
                        Circle()
                            .fill(isActive ? Color.green.opacity(0.45) : Color.green)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(isActive)
                    .help(isActive ? "Already recording" : "Start recording")

                    // Solid red Stop square. Faintly red when idle so the
                    // affordance reads as a button, fully red when armed.
                    Button(action: onStop) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isRecording ? Color.red : Color.red.opacity(0.45))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isRecording)
                    .help(isRecording ? "Stop recording" : "Not recording")
                }
            }

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
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRecording ? Color.red.opacity(0.6) : Color.gray.opacity(0.4), lineWidth: 1)
        )
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
