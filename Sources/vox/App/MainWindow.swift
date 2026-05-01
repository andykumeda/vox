import AppKit
import SwiftUI

/// Primary window for Vox. Sidebar nav with Home / Dictionary / Meeting / Settings /
/// Help. Auto-opens on launch and reappears on menu-bar icon click. Closing the window
/// hides it (does not quit) so dictation hotkeys keep working in the background.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    public static let shared = MainWindowController()

    private var window: NSWindow?
    let selection = SidebarSelection()

    private override init() { super.init() }

    public func showWindow() {
        if window == nil { build() }
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showHome()       { showWindow(section: .home) }
    public func showDictionary() { showWindow(section: .dictionary) }
    public func showMeeting()    { showWindow(section: .meeting) }
    public func showSettings()   { showWindow(section: .settings) }
    public func showHelp()       { showWindow(section: .help) }

    private func showWindow(section: SidebarItem) {
        selection.current = section
        showWindow()
    }

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Vox"
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 900, height: 520)
        win.tabbingMode = .disallowed
        win.delegate = self

        let host = NSHostingController(rootView: MainWindowRootView(selection: selection))
        win.contentViewController = host

        win.center()
        self.window = win
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
final class SidebarSelection: ObservableObject {
    @Published var current: SidebarItem = .home
}

private struct MainWindowRootView: View {
    @ObservedObject var selection: SidebarSelection

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarItem.allCases, selection: Binding(
                    get: { selection.current },
                    set: { if let v = $0 { selection.current = v } }
                )) { item in
                    Label(item.label, systemImage: item.systemImage).tag(item)
                }
                .listStyle(.sidebar)
                Divider()
                Button {
                    UpdaterAccess.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .navigationTitle("Vox")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection.current {
            case .home:       HomeView()
            case .dictionary: DictionaryDestinationView()
            case .meeting:    MeetingDestinationView()
            case .settings:   SettingsDestinationView()
            case .help:       HelpDestinationView()
            }
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case home, dictionary, meeting, settings, help
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home:       return "Home"
        case .dictionary: return "Dictionary"
        case .meeting:    return "Meeting"
        case .settings:   return "Settings"
        case .help:       return "Help"
        }
    }
    var systemImage: String {
        switch self {
        case .home:       return "house"
        case .dictionary: return "character.book.closed"
        case .meeting:    return "person.2.wave.2"
        case .settings:   return "gearshape"
        case .help:       return "questionmark.circle"
        }
    }
}

// MARK: - Destination placeholders (filled in by subsequent migrations)

private struct HomeView: View {
    @State private var totals: UsageTotals = UsageTracker.totals()
    @State private var dictationHistory: [DictationEntry] = []
    @State private var meetings: [TranscriptSession] = []

    private let meetingStore = MeetingTranscriptStore()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Vox")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                statsRow

                Divider()

                Text("Recent dictations")
                    .font(.title3)
                    .fontWeight(.semibold)
                if dictationHistory.isEmpty {
                    Text("No dictations yet — hold Fn to record one.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dictationHistory.prefix(20)) { entry in
                            dictationRow(entry)
                            Divider()
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }

                Divider()

                Text("Recent meetings")
                    .font(.title3)
                    .fontWeight(.semibold)
                if meetings.isEmpty {
                    Text("No meetings yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(meetings.prefix(10), id: \.id) { m in
                            meetingRow(m)
                            Divider()
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .dictationHistoryDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingTranscriptStoreDidChange)) { _ in
            reload()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(label: "Dictations", value: "\(totals.calls)")
            statCard(label: "Words", value: "\(totals.words)")
            statCard(label: "Audio", value: formatSeconds(totals.audioSeconds))
            statCard(label: "Spend", value: String(format: "$%.4f", totals.usd))
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded)).fontWeight(.semibold)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func dictationRow(_ e: DictationEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(dateFormatter.string(from: e.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(e.mode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
                Text("\(e.wordCount) words · \(String(format: "%.1f", e.durationSec))s")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text(e.text)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meetingRow(_ m: TranscriptSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.callout)
                Text("\(m.segments.count) segments · \(m.status.rawValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(dateFormatter.string(from: m.startedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() {
        totals = UsageTracker.totals()
        dictationHistory = DictationHistoryStore.shared.list().sorted { $0.timestamp > $1.timestamp }
        meetings = meetingStore.list()
    }

    private func formatSeconds(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm %ds", m, sec) }
        return "\(sec)s"
    }
}

private struct DictionaryDestinationView: View {
    var body: some View { DictionaryView() }
}

private struct MeetingDestinationView: View {
    var body: some View { MeetingTranscriptsView() }
}

private struct SettingsDestinationView: View {
    var body: some View { SettingsView(keychain: KeychainStore()) }
}

private struct HelpDestinationView: View {
    var body: some View { HelpView() }
}

private struct Placeholder: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.title)
            Text(note).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
