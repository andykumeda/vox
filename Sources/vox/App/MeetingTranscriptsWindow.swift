import AppKit
import Combine
import SwiftUI

@MainActor
public final class MeetingTranscriptsWindow {
    public static let shared = MeetingTranscriptsWindow()

    private var window: NSWindow?

    public func show() {
        if let window = window {
            bringToFront(window)
            return
        }
        let view = MeetingTranscriptsView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Meeting Transcripts"
        win.setContentSize(NSSize(width: 720, height: 480))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        // Follow the user across Spaces / full-screen apps so the transcript
        // browser stays reachable like the floating meeting HUD.
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        bringToFront(win)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class MeetingTranscriptsModel: ObservableObject {
    @Published var sessions: [TranscriptSession] = []
    @Published var selection: UUID?
    private let store = MeetingTranscriptStore()
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .meetingTranscriptStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    func reload() {
        sessions = store.list()
        if selection == nil { selection = sessions.first?.id }
    }

    func selected() -> TranscriptSession? {
        guard let id = selection else { return nil }
        return sessions.first { $0.id == id }
    }

    func delete(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = "Delete this transcript?"
        alert.informativeText = "This permanently removes the transcript and any kept audio."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.delete(id: id)
        } catch {
            dlog("MeetingTranscriptsModel delete failed: \(error)")
        }
        // Synchronously refresh so SwiftUI sees a single consistent state update:
        // sessions list without the deleted item, selection moved to the new first.
        sessions = store.list()
        selection = sessions.first?.id
    }

    func cancelActive(_ id: UUID) {
        if MeetingTranscriptionSession.shared.activeSessionID == id {
            MeetingTranscriptionSession.shared.cancel()
        }
    }

    func export(_ session: TranscriptSession, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.title).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = format.render(session: session)
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    enum ExportFormat {
        case plain, timestamped

        func render(session: TranscriptSession) -> String {
            let useSpeakerID = session.segments.contains { $0.speakerID != nil }
            func label(_ seg: TranscriptSegment) -> String {
                if useSpeakerID, let id = seg.speakerID { return "Speaker \(id)" }
                return seg.source == .local ? "You" : "Other"
            }
            switch self {
            case .plain:
                // Group consecutive same-speaker segments into one paragraph
                // labelled with the speaker. New speaker → blank line + new block.
                var out = ""
                var currentLabel: String? = nil
                for seg in session.segments {
                    let l = label(seg)
                    if l != currentLabel {
                        if !out.isEmpty { out += "\n\n" }
                        out += "\(l): \(seg.text)"
                        currentLabel = l
                    } else {
                        out += " " + seg.text
                    }
                }
                return out
            case .timestamped:
                return session.segments.map { seg in
                    "[\(formatTime(seg.startTime))] \(label(seg)): \(seg.text)"
                }.joined(separator: "\n")
            }
        }
        private func formatTime(_ t: Double) -> String {
            let total = Int(t)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%02d:%02d", m, s)
        }
    }
}

struct MeetingTranscriptsView: View {
    @StateObject private var model = MeetingTranscriptsModel()

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            detail.frame(minWidth: 420)
        }
        .frame(minWidth: 600, minHeight: 360)
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            ForEach(model.sessions, id: \.id) { session in
                SidebarRow(session: session, onCancel: { model.cancelActive(session.id) })
                    .tag(session.id)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let s = model.selected() {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.title).font(.headline)
                    Spacer()
                    Menu("Export") {
                        Button("Plain Text") { model.export(s, format: .plain) }
                        Button("Timestamped Text") { model.export(s, format: .timestamped) }
                    }
                    Button("Delete") { model.delete(s.id) }
                }.padding()
                Divider()
                if s.status == .failed, let reason = s.failureReason {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(reason)
                            .textSelection(.enabled)
                            .font(.callout)
                    }.padding()
                    Divider()
                }
                if let summary = s.summary, !summary.isEmpty {
                    DisclosureGroup {
                        // Cap the summary's vertical footprint so the transcript
                        // below stays readable on long summaries. Scrolls
                        // internally when the markdown overflows the cap.
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(summary)
                                .textSelection(.enabled)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                                .padding(.trailing, 8)
                        }
                        .frame(maxHeight: 180)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Summary").font(.subheadline).bold()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                }
                if !s.rawSegments.isEmpty, s.rawSegments != s.segments {
                    DisclosureGroup("Raw provider transcript comparison") {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(meetingComparison(s))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                }
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(s.segments.enumerated()), id: \.offset) { _, seg in
                            HStack(alignment: .top) {
                                Text(formatTime(seg.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(speakerLabel(seg))
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundStyle(speakerColor(seg))
                                    .frame(width: 76, alignment: .leading)
                                Text(seg.text).textSelection(.enabled)
                            }.padding(.horizontal)
                        }
                    }.padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
        } else if model.sessions.isEmpty {
            VStack(spacing: 8) {
                Text("No meeting transcripts yet.")
                    .foregroundStyle(.secondary)
                Text("Use the menu bar or Cmd+Shift+M to start a meeting recording.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Text("Select a meeting from the list.")
                    .foregroundStyle(.secondary)
                Text("\(model.sessions.count) saved.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func meetingComparison(_ session: TranscriptSession) -> String {
        let raw = session.rawSegments.map(\.text).joined(separator: " ")
        let final = session.segments.map(\.text).joined(separator: " ")
        return TranscriptComparison.diff(raw: raw, final: final)
    }

    private func formatTime(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func speakerLabel(_ seg: TranscriptSegment) -> String {
        if let id = seg.speakerID { return "Speaker \(id)" }
        return seg.source == .local ? "You" : "Other"
    }

    private func speakerColor(_ seg: TranscriptSegment) -> Color {
        // Local mic always = you; reserve green so it never collides with a
        // remote speaker color from the palette below.
        if seg.source == .local { return .green }
        if let id = seg.speakerID {
            let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .brown, .red]
            return palette[(id % palette.count + palette.count) % palette.count]
        }
        return .purple
    }
}

private struct SidebarRow: View {
    let session: TranscriptSession
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.body)
            HStack(spacing: 6) {
                Text(durationText).foregroundStyle(.secondary).font(.caption)
                statusBadge
                if session.status == .transcribing {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.borderless)
                }
            }
        }.padding(.vertical, 2)
    }

    private var durationText: String {
        guard let end = session.endedAt else { return "Recording…" }
        let secs = Int(end.timeIntervalSince(session.startedAt))
        let m = secs / 60, s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .recording:
            Text("Recording").foregroundStyle(.red).font(.caption)
        case .chunking:
            Text("Chunking…").foregroundStyle(.orange).font(.caption)
        case .transcribing:
            Text("Transcribing \(session.chunksCompleted)/\(session.chunksTotal)")
                .foregroundStyle(.orange).font(.caption)
        case .completed:
            Text("Done").foregroundStyle(.green).font(.caption)
        case .cancelled:
            Text("Cancelled").foregroundStyle(.secondary).font(.caption)
        case .failed:
            Text("Failed").foregroundStyle(.red).font(.caption)
        }
    }
}
