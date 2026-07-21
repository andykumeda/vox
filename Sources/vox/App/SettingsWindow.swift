import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

struct RecordingStorageUsage: Equatable, Sendable {
    let dictationBytes: UInt64
    let meetingBytes: UInt64

    static func load() async -> RecordingStorageUsage {
        await Task.detached(priority: .utility) {
            RecordingStorageUsage(
                dictationBytes: RecordingArchive.diskBytes(),
                meetingBytes: MeetingTranscriptStore().audioDiskBytes()
            )
        }.value
    }

    func formatted() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatted { formatter.string(fromByteCount: $0) }
    }

    func formatted(_ formatBytes: (Int64) -> String) -> String {
        let dictation = formatBytes(Int64(clamping: dictationBytes))
        let meetings = formatBytes(Int64(clamping: meetingBytes))
        return "On disk now: \(dictation) dictation, \(meetings) meetings."
    }
}

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedMessage: String?
    @State private var deepgramKey: String = ""
    @State private var showDeepgramKey = false
    @State private var deepgramSavedMessage: String?
    @State private var meetingProvider: MeetingProvider = AppSettings.meetingProvider
    @State private var keepOnClipboard: Bool = AppSettings.keepTranscriptionOnClipboard
    @State private var remoteControlMode: Bool = AppSettings.remoteControlModeEnabled
    @State private var modeOverride: ModeOverride = AppSettings.modeOverride
    @State private var smartCleanup: Bool = AppSettings.smartCleanupEnabled
    @State private var cleanupProfile: String = CleanupProfileStore.shared.load()
    @State private var cleanupProfileMessage: String?
    @State private var meetingMode: Bool = AppSettings.meetingModeEnabled
    @State private var meetingConsent: Bool = AppSettings.meetingConsentAcknowledged
    @State private var autoShowMeetingPanel: Bool = AppSettings.autoShowMeetingPanel
    @State private var meetingSummaryEnabled: Bool = AppSettings.meetingSummaryEnabled
    @State private var meetingBackendStatus: MeetingBackendStatus = MeetingPreflight.backendStatusProvider()
    @State private var audioRetention: AudioRetention = AppSettings.audioRetention
    @State private var model: TranscriptionModel = AppSettings.transcriptionModel
    @State private var totals: UsageTotals = UsageTracker.totals()
    @State private var storageUsageLine = "Calculating disk usage…"
    @State private var isRefreshingStorageUsage = false
    let keychain: KeychainStore
    private let deepgramKeychain = KeychainStore(account: "deepgram-api-key")
    private let cleanupProfileStore = CleanupProfileStore.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vox — Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.headline)
                HStack {
                    if showKey {
                        TextField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                }
                Text("Stored in macOS Keychain. Get a key at platform.openai.com/api-keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                Button("Clear") {
                    try? keychain.delete()
                    apiKey = ""
                    savedMessage = "Cleared."
                }
                if let msg = savedMessage {
                    Text(msg).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Deepgram API key")
                    .font(.headline)
                HStack {
                    if showDeepgramKey {
                        TextField("Token …", text: $deepgramKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Token …", text: $deepgramKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showDeepgramKey ? "Hide" : "Show") { showDeepgramKey.toggle() }
                }
                Text("Stored in macOS Keychain. Used for diarized meeting transcription. Get a key at console.deepgram.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save Deepgram key") { saveDeepgram() }
                    Button("Clear") {
                        try? deepgramKeychain.delete()
                        deepgramKey = ""
                        deepgramSavedMessage = "Cleared."
                    }
                    if let msg = deepgramSavedMessage {
                        Text(msg).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                Picker("", selection: $model) {
                    ForEach(TranscriptionModel.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .onChange(of: model) { newValue in
                    AppSettings.transcriptionModel = newValue
                }
                Text(String(format: "≈ $%.4f / minute of audio", model.usdPerMinute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Usage (lifetime)")
                    .font(.headline)
                Text("Calls: \(totals.calls)   Words: \(totals.words)")
                    .font(.system(.body, design: .monospaced))
                Text(String(format: "Audio: %.1f min   Cost: $%.3f",
                            totals.audioSeconds / 60.0, totals.usd))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Refresh") { totals = UsageTracker.totals() }
                    Button("Reset") {
                        UsageTracker.reset()
                        totals = UsageTracker.totals()
                    }
                }
                Text("Estimate based on audio duration × model rate. Output text tokens add a tiny extra charge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(.headline)
                Picker("", selection: Binding(
                    get: { modeOverride },
                    set: { newValue in
                        modeOverride = newValue
                        AppSettings.modeOverride = newValue
                    }
                )) {
                    ForEach(ModeOverride.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("Auto: dictation in Terminal/iTerm/Wave/etc gets command formatting (no period, no caps, dash/NATO/control); other apps get prose with sentence punctuation. Always prose: every dictation formatted as prose. Always command: every dictation formatted as a shell command (useful when dictating into a journal app or notes that hold shell commands you'll copy out later). The mode-toggle hotkey cycles through all three.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Smart cleanup (prose mode): remove false starts and self-corrections via gpt-4o-mini", isOn: Binding(
                    get: { smartCleanup },
                    set: { newValue in
                        smartCleanup = newValue
                        AppSettings.smartCleanupEnabled = newValue
                    }
                ))
                Text("Adds ~$0.0001 and ~1s latency per dictation. Triggers ('scratch that', 'new paragraph', 'new line') also activate when enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal cleanup instructions")
                        .font(.subheadline)
                    TextEditor(text: $cleanupProfile)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    HStack {
                        Button("Save") { saveCleanupProfile() }
                        Button("Reset") { resetCleanupProfile() }
                        Button("Reveal File") { revealCleanupProfile() }
                        if let msg = cleanupProfileMessage {
                            Text(msg).foregroundStyle(.secondary)
                        }
                    }
                    Text("Optional guidance for preserving your voice, wording, and style. Empty uses the default conservative cleanup behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting Transcription (Beta)")
                    .font(.headline)
                Toggle("Enable Meeting Mode", isOn: Binding(
                    get: { meetingMode },
                    set: { newValue in
                        meetingMode = newValue
                        AppSettings.meetingModeEnabled = newValue
                        NotificationCenter.default.post(name: .meetingModeChanged, object: nil)
                        // Surface the Screen Recording prompt the first time Meeting Mode is enabled.
                        // CGRequestScreenCaptureAccess is a one-shot system prompt; if already
                        // decided (granted or denied), the call is a no-op.
                        if newValue && !CGPreflightScreenCaptureAccess() {
                            _ = CGRequestScreenCaptureAccess()
                        }
                        meetingBackendStatus = MeetingPreflight.backendStatusProvider()
                    }
                ))
                Text("Adds Start/Stop Meeting Transcript actions to the menu bar. Off by default. Does not affect dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if meetingMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transcription provider")
                            .font(.subheadline)
                        Picker("", selection: Binding(
                            get: { meetingProvider },
                            set: { newValue in
                                meetingProvider = newValue
                                AppSettings.meetingProvider = newValue
                            }
                        )) {
                            ForEach(MeetingProvider.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        Text("Deepgram diarizes individual speakers (Speaker 0/1/…). OpenAI Whisper only distinguishes your mic (You) vs the system audio loopback (Other). Deepgram needs its own API key above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "≈ $%.2f / hour of audio (mic + system audio billed separately, so ~2× meeting length)", meetingProvider.usdPerHour))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("I acknowledge meeting audio will be captured and sent to the selected transcription provider", isOn: Binding(
                        get: { meetingConsent },
                        set: { newValue in
                            meetingConsent = newValue
                            AppSettings.meetingConsentAcknowledged = newValue
                        }
                    ))
                    Text("Required once before the first meeting capture. Confirm with all participants per local consent law.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: meetingBackendStatus.available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(meetingBackendStatus.available ? .green : .orange)
                        Text(meetingBackendStatus.detail)
                            .font(.caption)
                    }

                    Toggle("Auto-show meeting panel when a call starts", isOn: Binding(
                        get: { autoShowMeetingPanel },
                        set: { newValue in
                            autoShowMeetingPanel = newValue
                            AppSettings.autoShowMeetingPanel = newValue
                        }
                    ))
                    Text("Detects Teams, Zoom, Meet (web), Webex, Slack huddle, Discord, Skype calls by polling window titles. Pops the floating panel — does NOT auto-record. You still click Record to start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Generate meeting summary after transcription (gpt-4o-mini)", isOn: Binding(
                        get: { meetingSummaryEnabled },
                        set: { newValue in
                            meetingSummaryEnabled = newValue
                            AppSettings.meetingSummaryEnabled = newValue
                        }
                    ))
                    Text("Adds ~$0.0005 per meeting. Summary appears at the top of the transcript browser. Won't run if no API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recordings storage")
                    .font(.headline)
                Picker("Delete audio older than", selection: Binding(
                    get: { audioRetention },
                    set: { newValue in
                        audioRetention = newValue
                        AppSettings.audioRetention = newValue
                    }
                )) {
                    ForEach(AudioRetention.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                Text("Transcripts are kept indefinitely. Only the raw audio (dictation WAVs and meeting recordings) is purged. Sweep runs at app launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Reveal Dictation Recordings") {
                        NSWorkspace.shared.activateFileViewerSelecting([RecordingArchive.directory()])
                    }
                    Button("Reveal Meeting Recordings") {
                        NSWorkspace.shared.activateFileViewerSelecting([MeetingTranscriptStore.defaultRoot()])
                    }
                }
                HStack(spacing: 6) {
                    Text(storageUsageLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isRefreshingStorageUsage {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Calculating recordings storage")
                    }
                    Button("Refresh") {
                        Task { await refreshStorageUsage() }
                    }
                    .controlSize(.small)
                    .disabled(isRefreshingStorageUsage)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste behavior")
                    .font(.headline)
                Toggle("Keep transcription on clipboard after paste", isOn: Binding(
                    get: { keepOnClipboard },
                    set: { newValue in
                        keepOnClipboard = newValue
                        AppSettings.keepTranscriptionOnClipboard = newValue
                    }
                ))
                Text("When on, the transcribed text stays on your clipboard so you can Cmd+V again if focus moved away. Your prior clipboard contents are overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Remote control mode", isOn: Binding(
                    get: { remoteControlMode },
                    set: { newValue in
                        remoteControlMode = newValue
                        AppSettings.remoteControlModeEnabled = newValue
                    }
                ))
                Text("Use this when controlling this Mac through VNC, Screen Sharing, or RustDesk. Vox types the transcript directly instead of using the clipboard, avoiding remote clipboard sync pasting an older recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Dictation history")
                    .font(.headline)
                HStack {
                    Text("Keep entries for")
                    Picker("", selection: Binding(
                        get: { AppSettings.dictationHistoryRetention },
                        set: { AppSettings.dictationHistoryRetention = $0 }
                    )) {
                        ForEach(DictationHistoryRetention.allCases, id: \.self) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                    Spacer()
                    Button("Clear all history") {
                        DictationHistoryStore.shared.clear()
                    }
                }
                Text("Older entries are pruned automatically. \"Forever\" never prunes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Updates")
                    .font(.headline)
                Button("Check for Updates…") {
                    UpdaterAccess.checkForUpdates()
                }
                Text("Vox checks automatically once per day. Use this to check immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.headline)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Open Input Monitoring Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                Button("Open Microphone Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                Button("Open Screen Recording Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkeys").font(.headline)

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.recordHotkey },
                        set: { AppSettings.recordHotkey = $0 }
                    ),
                    label: "Record dictation",
                    allowTriggerModePicker: true
                )

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.modeToggleHotkey },
                        set: { AppSettings.modeToggleHotkey = $0 }
                    ),
                    label: "Toggle mode (auto / force prose)",
                    allowTriggerModePicker: false
                )

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.meetingHotkey },
                        set: { AppSettings.meetingHotkey = $0 }
                    ),
                    label: "Start / stop meeting transcript",
                    allowTriggerModePicker: false
                )

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.pasteLastHotkey },
                        set: { AppSettings.pasteLastHotkey = $0 }
                    ),
                    label: "Paste last transcription (disabled by default)",
                    allowTriggerModePicker: false
                )

                Button("Reset all to defaults") {
                    AppSettings.recordHotkey = .defaultRecord
                    AppSettings.modeToggleHotkey = .defaultModeToggle
                    AppSettings.meetingHotkey = .defaultMeeting
                    AppSettings.pasteLastHotkey = .defaultPasteLast
                }
                .controlSize(.small)
            }

        }
        .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            apiKey = keychain.read() ?? ""
            deepgramKey = deepgramKeychain.read() ?? ""
            totals = UsageTracker.totals()
            model = AppSettings.transcriptionModel
            remoteControlMode = AppSettings.remoteControlModeEnabled
            modeOverride = AppSettings.modeOverride
            smartCleanup = AppSettings.smartCleanupEnabled
            cleanupProfile = cleanupProfileStore.load()
            meetingMode = AppSettings.meetingModeEnabled
            meetingConsent = AppSettings.meetingConsentAcknowledged
            meetingProvider = AppSettings.meetingProvider
            meetingBackendStatus = MeetingPreflight.backendStatusProvider()
            audioRetention = AppSettings.audioRetention
        }
        .task {
            await refreshStorageUsage()
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        do {
            try keychain.save(trimmed)
            savedMessage = "Saved."
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveDeepgram() {
        let trimmed = deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines)
        deepgramKey = trimmed
        do {
            try deepgramKeychain.save(trimmed)
            deepgramSavedMessage = "Saved."
        } catch {
            deepgramSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveCleanupProfile() {
        do {
            try cleanupProfileStore.save(cleanupProfile)
            cleanupProfileMessage = "Saved."
        } catch {
            cleanupProfileMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func resetCleanupProfile() {
        do {
            try cleanupProfileStore.reset()
            cleanupProfile = ""
            cleanupProfileMessage = "Reset."
        } catch {
            cleanupProfileMessage = "Reset failed: \(error.localizedDescription)"
        }
    }

    private func revealCleanupProfile() {
        do {
            try cleanupProfileStore.ensureFileExists()
            NSWorkspace.shared.activateFileViewerSelecting([cleanupProfileStore.fileURL])
        } catch {
            cleanupProfileMessage = "Reveal failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshStorageUsage() async {
        guard !isRefreshingStorageUsage else { return }
        isRefreshingStorageUsage = true
        defer { isRefreshingStorageUsage = false }

        let usage = await RecordingStorageUsage.load()
        guard !Task.isCancelled else { return }
        storageUsageLine = usage.formatted()
    }
}

struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.spoken).font(.system(.body, design: .monospaced))
                    Text("→").foregroundStyle(.secondary)
                    Text(entry.replacement.isEmpty ? "(delete)" : entry.replacement)
                        .font(.system(.body, design: .monospaced))
                }
                HStack(spacing: 8) {
                    Text(entry.mode.rawValue).font(.caption).foregroundStyle(.secondary)
                    if entry.startsWith {
                        Text("start").font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.isBuiltIn {
                        Text("built-in").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            if !entry.isBuiltIn {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DictionaryEditSheet: View {
    @State var entry: DictionaryEntry
    let isNew: Bool
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add entry" : "Edit entry").font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spoken").font(.caption)
                TextField("e.g. vox", text: $entry.spoken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Replacement").font(.caption)
                TextField("e.g. Vox", text: $entry.replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                Picker("Mode", selection: $entry.mode) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .frame(maxWidth: 180)

                Toggle("Match only at start", isOn: $entry.startsWith)
                Toggle("Case-insensitive", isOn: $entry.caseInsensitive)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") { onSave(entry) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.spoken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }
}

struct HotkeyRecorderField: View {
    @Binding var hotkey: Hotkey
    let label: String
    let allowTriggerModePicker: Bool
    @State private var isRecording = false
    @State private var recorder: HotkeyRecorder?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption)
            HStack(spacing: 8) {
                Button {
                    startRecording()
                } label: {
                    Text(isRecording ? "Press your combo…" : displayString(hotkey))
                        .frame(minWidth: 200, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if allowTriggerModePicker {
                    Picker("", selection: $hotkey.triggerMode) {
                        Text("Press-and-hold").tag(TriggerMode.pressHold)
                        Text("Tap-to-toggle").tag(TriggerMode.tapToggle)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                Button(hotkey.enabled ? "Disable" : "Enable") {
                    hotkey.enabled.toggle()
                }
            }
            if let h = hint {
                Text(h).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        hint = nil
        let r = HotkeyRecorder(existingTriggerMode: hotkey.triggerMode)
        recorder = r
        let started = r.start { [hotkey] result in
            isRecording = false
            recorder = nil
            if let captured = result, captured.isValid {
                self.hotkey = Hotkey(
                    key: captured.key,
                    modifiers: captured.modifiers,
                    triggerMode: hotkey.triggerMode,
                    enabled: true
                )
            } else if result != nil {
                hint = "Combo needs at least one modifier."
            } // nil = cancelled / timeout, leave existing binding
        }
        if !started {
            isRecording = false
            recorder = nil
            hint = "Another hotkey field is already listening."
        }
    }
}

private func displayString(_ h: Hotkey) -> String {
    if !h.enabled { return "(disabled)" }
    switch h.key {
    case .fn:
        return "Fn"
    case .modifier(let m):
        switch m {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        }
    case .keycode(let kc):
        let prefix = displayModifiers(h.modifiers)
        return prefix + keyName(forKeycode: kc)
    }
}

private func displayModifiers(_ mods: Set<Modifier>) -> String {
    var s = ""
    if mods.contains(.control) { s += "⌃" }
    if mods.contains(.option)  { s += "⌥" }
    if mods.contains(.shift)   { s += "⇧" }
    if mods.contains(.command) { s += "⌘" }
    return s
}

private func keyName(forKeycode kc: UInt16) -> String {
    let map: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab", UInt16(kVK_Escape): "Esc",
    ]
    return map[kc] ?? "key(\(kc))"
}

final class SettingsWindowController: NSWindowController {
    convenience init(keychain: KeychainStore) {
        let hosting = NSHostingController(rootView: SettingsView(keychain: keychain))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vox"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }
}
