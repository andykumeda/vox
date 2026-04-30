import AppKit
import Combine
import SwiftUI

@MainActor
public final class MeetingTranscriptsWindow {
    public static let shared = MeetingTranscriptsWindow()

    private var window: NSWindow?

    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MeetingTranscriptsView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Meeting Transcripts"
        win.setContentSize(NSSize(width: 720, height: 480))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        if alert.runModal() == .alertFirstButtonReturn {
            try? store.delete(id: id)
            reload()
        }
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
            switch self {
            case .plain:
                var out = ""
                var lastEnd: Double = -1
                for seg in session.segments {
                    if lastEnd >= 0, seg.startTime - lastEnd > 2.0 { out += "\n\n" }
                    else if !out.isEmpty { out += " " }
                    out += seg.text
                    lastEnd = seg.endTime
                }
                return out
            case .timestamped:
                return session.segments.map { seg in
                    "[\(formatTime(seg.startTime))] \(seg.text)"
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

private struct MeetingTranscriptsView: View {
    @StateObject private var model = MeetingTranscriptsModel()

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 240, idealWidth: 260)
            detail
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(s.segments.enumerated()), id: \.offset) { _, seg in
                            HStack(alignment: .top) {
                                Text(formatTime(seg.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(seg.text).textSelection(.enabled)
                            }.padding(.horizontal)
                        }
                    }.padding(.vertical, 6)
                }
            }
        } else {
            Text("No transcripts yet.").foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
