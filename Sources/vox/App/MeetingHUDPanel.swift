import AppKit
import SwiftUI

/// Floating panel near the menu bar that shows meeting recording state.
/// Visible only while `MeetingTranscriptionSession.shared.isActive == true`.
@MainActor
public final class MeetingHUDPanel {
    public static let shared = MeetingHUDPanel()

    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var isVisible = false

    private init() {}

    /// Idempotent. Builds and shows the panel if not already visible. Safe to call from
    /// session start / hotkey handlers / menu actions.
    public func show() {
        if isVisible, let panel = panel {
            panel.orderFrontRegardless()
            return
        }

        let view = MeetingHUDView(onStop: {
            Task { @MainActor in
                try? await MeetingTranscriptionSession.shared.stop()
            }
        })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 44)

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
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hosting
        positionNearMenuBar(p)
        p.orderFrontRegardless()
        self.panel = p
        self.isVisible = true

        // Light timer to refresh the elapsed-time label and self-dismiss when the
        // session goes inactive (cancel/complete/fail).
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if !MeetingTranscriptionSession.shared.isActive {
                    self.hide()
                    return
                }
                if let v = self.panel?.contentView as? NSHostingView<MeetingHUDView> {
                    v.rootView = MeetingHUDView(onStop: v.rootView.onStop)
                }
            }
        }
    }

    public func hide() {
        pollTimer?.invalidate()
        pollTimer = nil
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }

    private func positionNearMenuBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        // Top-right under menu bar, with small inset.
        let inset: CGFloat = 12
        let menuBarHeight: CGFloat = 24
        let frame = panel.frame
        let x = screen.frame.maxX - frame.width - inset
        let y = screen.frame.maxY - frame.height - menuBarHeight - inset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
private struct MeetingHUDView: View {
    let onStop: () -> Void
    @State private var nowTick = Date()

    private var startedAt: Date? {
        // Read from the session via the store; cheap because store reads JSON only on demand.
        guard let id = MeetingTranscriptionSession.shared.activeSessionID else { return nil }
        return MeetingTranscriptionSession.shared.store.load(id: id)?.startedAt
    }

    private var statusLabel: String {
        switch MeetingTranscriptionSession.shared.statusSnapshot {
        case .recording:    return "Recording"
        case .chunking:     return "Chunking…"
        case .transcribing:
            let s = MeetingTranscriptionSession.shared.store.load(
                id: MeetingTranscriptionSession.shared.activeSessionID ?? UUID()
            )
            if let s = s {
                return "Transcribing \(s.chunksCompleted)/\(s.chunksTotal)"
            }
            return "Transcribing…"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(MeetingTranscriptionSession.shared.isRecording ? 1.0 : 0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusLabel).font(.system(size: 12, weight: .semibold))
                Text(elapsed).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onStop) {
                Image(systemName: "stop.fill")
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.6), lineWidth: 1)
        )
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            nowTick = date
        }
    }

    private var elapsed: String {
        guard let start = startedAt else { return "--:--" }
        let secs = Int(nowTick.timeIntervalSince(start))
        let m = secs / 60, s = secs % 60
        if secs >= 3600 {
            let h = secs / 3600, mm = (secs % 3600) / 60
            return String(format: "%d:%02d:%02d", h, mm, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
