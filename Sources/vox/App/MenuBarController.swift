import AppKit
import ApplicationServices
import Sparkle

/// Mutex hook: returns true when something else (currently only meeting recording)
/// has taken over the audio path and dictation hotkey must be ignored.
/// Production resolves to `MeetingTranscriptionSession.shared.isRecording`.
/// Tests swap this for a stub.
public enum DictationMutex {
    public static var isBlocked: () -> Bool = {
        MeetingTranscriptionSession.shared.isRecording
    }
}

enum MenuIconState {
    case idle, recording, transcribing, error
}

final class MenuBarController: NSObject {
    static let pasteLastFocusSettleDelay: TimeInterval = 0.20

    /// Serializes dictation paste and Paste Last so clipboard/remote waits cannot interleave.
    private actor PasteGate {
        func run(_ body: @Sendable () async -> Void) async {
            await body()
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let keychain = KeychainStore()
    private let contextDetector = ContextDetector()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let injector = TextInjector()
    private let pasteGate = PasteGate()
    private let sound = SoundPlayer()
    private lazy var transcriber = OpenAITranscriber(
        modelProvider: { AppSettings.transcriptionModel.rawValue },
        apiKeyProvider: { [keychain] in keychain.read() }
    )
    private lazy var liveLLMCleaner: CleanupProcessor.LLMCleanFunc = makeLiveLLMCleaner(
        apiKeyProvider: { [keychain] in keychain.read() },
        profileProvider: { CleanupProfileStore.shared.load() },
        dictionaryProvider: { DictionaryStore.loadEntriesFromDisk() }
    )
    private lazy var updaterController: SPUStandardUpdaterController = {
        let c = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        UpdaterAccess.controller = c
        return c
    }()
    private var helpWindowController: HelpWindowController?
    private let meetingDetector = MeetingDetector()

    private var currentMode: TranscriptionMode = .prose
    private var currentVerbatim: Bool = false
    private var pulseTimer: Timer?
    private var state: MenuIconState = .idle {
        didSet { refreshIcon() }
    }

    private static func elapsedString(since startedAt: Date) -> String {
        String(format: "%.3f", Date().timeIntervalSince(startedAt))
    }

    @discardableResult
    static func warmDictationAPIKey(
        apiKeyProvider: () -> String?,
        log: (String) -> Void = { message in dlog(message) }
    ) -> Bool {
        let startedAt = Date()
        let raw = apiKeyProvider()
        let hasKey = raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        log("dictation api key warmup elapsed=\(elapsedString(since: startedAt))s has_key=\(hasKey)")
        return hasKey
    }

    func start() {
        configureMenu()
        refreshIcon()

        let keychain = keychain
        DispatchQueue.global(qos: .utility).async {
            _ = Self.warmDictationAPIKey(apiKeyProvider: { keychain.read() })
        }

        hotkey.onRecordPress = { [weak self] verbatim in
            dlog("Fn press verbatim=\(verbatim)")
            self?.beginRecording(verbatim: verbatim)
        }
        hotkey.onRecordRelease = { [weak self] in
            dlog("Fn release")
            self?.endRecordingAndTranscribe()
        }
        hotkey.onModeToggle = { [weak self] in
            self?.handleModeToggle()
        }
        hotkey.onMeetingToggle = { [weak self] in
            self?.handleMeetingToggle()
        }
        hotkey.onPasteLast = { [weak self] in
            self?.pasteLastTranscription()
        }

        NotificationCenter.default.addObserver(
            forName: .recordHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .modeToggleHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }

        NotificationCenter.default.addObserver(
            forName: .meetingModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureMenu()
        }
        NotificationCenter.default.addObserver(
            forName: .meetingHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .pasteLastHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .autoShowMeetingPanelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureMeetingDetector()
        }
        NotificationCenter.default.addObserver(
            forName: .meetingTranscriptStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshIcon()
        }
        NotificationCenter.default.addObserver(
            forName: .dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureMenu()
        }
        // Refresh menu-bar icon when the frontmost app changes so the mode badge
        // reflects auto-detected command vs prose for the new context.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshIcon()
        }

        Task {
            let granted = await recorder.requestPermission()
            dlog("mic permission granted=\(granted)")
        }

        meetingDetector.onMeetingStarted = { [weak self] in
            // Don't pop the panel mid-recording; HUD is already up. Don't
            // pop if user disabled auto-show after we started.
            // We DO allow popping while a previous session is just
            // chunking/transcribing in the background — the panel shows
            // status and the next meeting's controls are ready when the
            // previous one finishes.
            guard self != nil else { return }
            guard AppSettings.autoShowMeetingPanel else { return }
            guard !MeetingTranscriptionSession.shared.isRecording else { return }
            dlog("MeetingDetector: meeting started — showing HUD")
            Task { @MainActor in MeetingHUDPanel.shared.show() }
        }
        reconfigureMeetingDetector()

        let hkStarted = hotkey.start()
        dlog("hotkey.start() -> \(hkStarted)")
        if !hkStarted {
            state = .error
            presentAlert(
                title: "Couldn't start hotkey listener",
                message: "Grant Input Monitoring permission in System Settings, then quit and relaunch Vox."
            )
        }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        dlog("AXIsProcessTrusted=\(trusted)")
    }

    private func configureMenu() {
        // Eagerly trigger the updater lazy so SPUStandardUpdaterController.start() runs
        // and UpdaterAccess.controller is populated before the user clicks anything.
        _ = updaterController

        let menu = NSMenu()
        let version = NSMenuItem(title: "Vox \(Self.appVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Home", symbol: "house",
            action: #selector(openMainWindow)
        ))
        menu.addItem(makeMenuItem(
            title: "Meeting", symbol: "person.2.wave.2",
            action: #selector(openMeetingPanel)
        ))
        menu.addItem(makeMenuItem(
            title: "Dictionary", symbol: "character.book.closed",
            action: #selector(openDictionary)
        ))
        menu.addItem(.separator())
        let pasteLastItem = makeMenuItem(
            title: "Paste Last Transcription",
            symbol: "doc.on.clipboard",
            action: #selector(pasteLastTranscriptionMenuAction)
        )
        pasteLastItem.isEnabled = (DictationHistoryStore.shared.last() != nil)
        menu.addItem(pasteLastItem)
        let remoteControlItem = makeMenuItem(
            title: "Remote Control Mode",
            symbol: "display",
            action: #selector(toggleRemoteControlMode)
        )
        remoteControlItem.state = AppSettings.remoteControlModeEnabled ? .on : .off
        menu.addItem(remoteControlItem)
        let ignoreRecordHotkeyItem = makeMenuItem(
            title: "Ignore Record Hotkey on This Mac",
            symbol: "keyboard",
            action: #selector(toggleIgnoreRecordHotkey)
        )
        ignoreRecordHotkeyItem.state = AppSettings.ignoreRecordHotkey ? .on : .off
        menu.addItem(ignoreRecordHotkeyItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Settings", symbol: "gearshape",
            action: #selector(openSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath",
            action: #selector(checkForUpdatesAction)
        ))
        menu.addItem(makeMenuItem(
            title: "Help", symbol: "questionmark.circle",
            action: #selector(openHelp)
        ))
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Vox",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func makeMenuItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func openMainWindow() {
        Task { @MainActor in MainWindowController.shared.showHome() }
    }

    @objc private func openMeetingPanel() {
        Task { @MainActor in MainWindowController.shared.showMeeting() }
    }

    @objc private func openDictionary() {
        Task { @MainActor in MainWindowController.shared.showDictionary() }
    }

    @objc private func openSettings() {
        Task { @MainActor in MainWindowController.shared.showSettings() }
    }

    @objc private func openHelp() {
        Task { @MainActor in MainWindowController.shared.showHelp() }
    }

    @objc private func pasteLastTranscriptionMenuAction() {
        pasteLastTranscription()
    }

    @objc private func toggleRemoteControlMode() {
        AppSettings.remoteControlModeEnabled.toggle()
        dlog("remote control mode -> \(AppSettings.remoteControlModeEnabled)")
        configureMenu()
    }

    @objc private func toggleIgnoreRecordHotkey() {
        AppSettings.ignoreRecordHotkey.toggle()
        dlog("ignore record hotkey -> \(AppSettings.ignoreRecordHotkey)")
        configureMenu()
    }

    /// Pastes the most recent dictation entry's text into the focused app.
    /// Triggered by the menu item or by the optional pasteLast global hotkey.
    private func pasteLastTranscription() {
        guard state == .idle else {
            dlog("paste last ignored — dictation busy state=\(state)")
            sound.play(.error)
            return
        }
        guard let entry = DictationHistoryStore.shared.last(), !entry.text.isEmpty else {
            dlog("paste last requested with no dictation history")
            sound.play(.error)
            return
        }
        let injector = self.injector
        let pasteGate = self.pasteGate
        let text = entry.text
        let keepOnClipboard = AppSettings.keepTranscriptionOnClipboard
        let delay = Self.pasteLastFocusSettleDelay
        dlog("paste last scheduled chars=\(text.count) delay=\(delay)s")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await pasteGate.run {
                await injector.pasteAsync(text, keepOnClipboard: keepOnClipboard)
            }
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    @objc private func checkForUpdatesAction() {
        updaterController.checkForUpdates(nil)
    }

    private func appIconForMenuBar(
        badgeColor: NSColor? = nil,
        commandMode: Bool = false
    ) -> NSImage? {
        let base: NSImage? = {
            if commandMode, let cmd = NSImage(named: "AppIcon-Command") { return cmd }
            return NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        }()
        guard let base else { return nil }
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        result.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        if let badgeColor {
            let d: CGFloat = 8
            let badgeRect = NSRect(
                x: size.width - d - 0.5,
                y: size.height - d - 0.5,
                width: d, height: d
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
            badgeColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    /// Returns the mode currently in effect: explicit override if set, otherwise
    /// `ContextDetector.modeForFrontmost()`. Used to drive the menu-bar mode badge so
    /// terminal mode is always visually distinguishable from prose.
    private func effectiveMode() -> TranscriptionMode {
        switch AppSettings.modeOverride {
        case .auto:    return contextDetector.modeForFrontmost()
        case .prose:   return .prose
        case .command: return .command
        }
    }

    private func whiteBackgroundIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: 4, yRadius: 4)
        path.fill()
        let candidates = ["text.bubble", "bubble.left", "bubble.left.fill", "waveform"]
        if let glyph = candidates.lazy
            .compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") })
            .first {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.black])
            let tinted = glyph.withSymbolConfiguration(cfg) ?? glyph
            tinted.draw(in: NSRect(x: 2, y: 2, width: 14, height: 14))
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func tintedSymbol(color: NSColor) -> NSImage? {
        let candidates = ["text.bubble.fill", "bubble.left.fill", "waveform", "mic.fill"]
        let base = candidates.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") }
            .first
        let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
        let tinted = base?.withSymbolConfiguration(cfg)
        tinted?.isTemplate = false
        return tinted
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }

        // Meeting capture takes visual priority over dictation states. The icon, color,
        // pulse and tooltip are all distinct so the user can never miss it.
        if MeetingTranscriptionSession.shared.isActive {
            let status = MeetingTranscriptionSession.shared.statusSnapshot
            let symbol: String
            let color: NSColor
            let tooltip: String
            switch status {
            case .recording:
                symbol = "record.circle.fill"; color = .systemRed
                tooltip = "Vox — MEETING RECORDING (click menu → Stop Meeting Transcript)"
            case .chunking, .transcribing:
                symbol = "waveform.circle.fill"; color = .systemOrange
                tooltip = "Vox — meeting transcribing…"
            default:
                symbol = "record.circle.fill"; color = .systemRed
                tooltip = "Vox — meeting active"
            }
            let candidates = [symbol, "record.circle", "circle.fill", "mic.fill"]
            let base = candidates.lazy
                .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox meeting") }
                .first
            let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
            let tinted = base?.withSymbolConfiguration(cfg)
            tinted?.isTemplate = false
            button.image = tinted
            button.contentTintColor = nil
            button.title = (button.image == nil) ? "● REC" : ""
            button.toolTip = tooltip
            if status == .recording {
                startPulsing()
            } else {
                stopPulsing()
            }
            return
        }

        let cmd = (effectiveMode() == .command)

        switch state {
        case .idle:
            button.image = appIconForMenuBar(commandMode: cmd)
            button.contentTintColor = nil
        case .recording:
            button.image = appIconForMenuBar(badgeColor: .systemRed, commandMode: cmd)
            button.contentTintColor = nil
        case .transcribing:
            button.image = appIconForMenuBar(badgeColor: .systemOrange, commandMode: cmd)
            button.contentTintColor = nil
        case .error:
            let candidates = ["exclamationmark.triangle", "exclamationmark.circle"]
            let base = candidates.lazy
                .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") }
                .first
            base?.isTemplate = true
            button.image = base
            button.contentTintColor = NSColor.labelColor
        }
        // Fallback: status item collapses to zero width if image is nil.
        button.title = (button.image == nil) ? "Vox" : ""
        if state == .transcribing {
            startPulsing()
        } else {
            stopPulsing()
        }
        button.toolTip = {
            switch state {
            case .idle: return "Vox — idle"
            case .recording: return "Vox — recording…"
            case .transcribing: return "Vox — transcribing…"
            case .error: return "Vox — error"
            }
        }()
    }

    public func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        let controller = helpWindowController
        Task { @MainActor in
            controller?.show()
        }
    }

    @objc private func showHelpAction(_ sender: Any?) {
        showHelp()
    }

    @objc private func startMeetingTranscript() {
        let result = MeetingPreflight.gate(hasAPIKey: keychain.read()?.isEmpty == false)
        if case .failure(let err) = result {
            dlog("meeting gate denied: \(err)")
            presentMeetingError(err.userMessage)
            return
        }
        if state == .recording {
            presentMeetingError("Finish current dictation before starting a meeting.")
            return
        }
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.start()
                MeetingHUDPanel.shared.show()
            } catch {
                self.presentMeetingError("Could not start meeting: \(error)")
            }
        }
    }

    @objc private func stopMeetingTranscript() {
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.stop()
                MeetingTranscriptsWindow.shared.show()
            } catch {
                self.presentMeetingError("Could not stop meeting: \(error)")
            }
        }
    }

    @objc private func showMeetingTranscripts() {
        Task { @MainActor in
            MeetingTranscriptsWindow.shared.show()
        }
    }

    private func presentMeetingError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Meeting Transcription"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func handleModeToggle() {
        // Toggle directly between prose and command based on the currently effective mode.
        // Skipping .auto means a single press is always visible (was: auto→prose→command
        // could swallow the first press when auto already resolved to the same mode).
        AppSettings.modeOverride = (effectiveMode() == .command) ? .prose : .command
        refreshIcon()
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func reconfigureHotkey() {
        hotkey.stop()
        hotkey.configure(
            record: AppSettings.recordHotkey,
            modeToggle: AppSettings.modeToggleHotkey,
            meeting: AppSettings.meetingHotkey,
            pasteLast: AppSettings.pasteLastHotkey
        )
        _ = hotkey.start()
    }

    private func reconfigureMeetingDetector() {
        if AppSettings.autoShowMeetingPanel {
            meetingDetector.start()
        } else {
            meetingDetector.stop()
        }
    }

    private func handleMeetingToggle() {
        // Hotkey now toggles the floating meeting panel rather than starting/
        // stopping the session directly. The session itself is started or
        // stopped only when the user clicks Record/Stop in the panel.
        Task { @MainActor in
            MeetingHUDPanel.shared.toggle()
        }
    }

    // MARK: - Record / Transcribe

    private func beginRecording(verbatim: Bool = false) {
        guard state == .idle else { return }
        if AppSettings.ignoreRecordHotkey {
            dlog("dictation Fn ignored — record hotkey disabled on this Mac")
            return
        }
        if DictationMutex.isBlocked() {
            dlog("dictation Fn ignored — meeting recording active")
            // Audible cue so the user notices their dictation isn't going through.
            NSSound(named: NSSound.Name("Funk"))?.play()
            return
        }
        currentVerbatim = verbatim
        switch AppSettings.modeOverride {
        case .auto:    currentMode = contextDetector.modeForFrontmost()
        case .prose:   currentMode = .prose
        case .command: currentMode = .command
        }
        do {
            try recorder.start(mode: currentMode == .prose ? "prose" : "command")
            state = .recording
            sound.play(.start)
        } catch {
            state = .error
            sound.play(.error)
            NSLog("[vox] recorder.start failed: \(error)")
        }
    }

    private func endRecordingAndTranscribe() {
        guard state == .recording else { return }
        let recordingURL = recorder.stop()
        sound.play(.stop)
        let mode = currentMode

        guard let url = recordingURL else {
            dlog("recorder.stop returned no file")
            state = .idle
            return
        }
        // The recording is already on disk (streamed during capture). Read it
        // back as a buffer for the transcription API call.
        let wav = (try? Data(contentsOf: url)) ?? Data()
        dlog("recording saved: \(url.path) bytes=\(wav.count)")

        // Silence gate: skip the transcription API on clearly empty clips.
        // Whisper hallucinates / echoes the system prompt when fed silence.
        // Tiered by duration so quiet-but-real long recordings still transcribe.
        let (durationSec, rms) = wavStats(wav)
        dlog("wav bytes=\(wav.count) duration=\(durationSec)s rms=\(rms) mode=\(mode)")
        let silenceGated: Bool = {
            if durationSec < 0.35 { return true }
            if durationSec < 2.0 && rms < 150 { return true }
            if rms < 40 { return true }
            return false
        }()
        if silenceGated {
            dlog("silence gate tripped — skipping transcription")
            state = .idle
            return
        }

        state = .transcribing

        Task { [weak self] in
            guard let self else { return }
            let pipelineStartedAt = Date()
            dlog("dictation pipeline started duration=\(durationSec)s bytes=\(wav.count) mode=\(mode)")
            do {
                let sttStartedAt = Date()
                let raw = try await self.transcriber.transcribe(wav: wav, mode: mode)
                let rawMetrics = textLogMetrics(label: "raw", text: raw)
                dlog("dictation timing stt=\(Self.elapsedString(since: sttStartedAt))s total=\(Self.elapsedString(since: pipelineStartedAt))s \(rawMetrics)")

                // Hallucination guard. gpt-4o-mini-transcribe occasionally loops on
                // short / noisy audio and emits a runaway repetitive cascade
                // (e.g. "rm -rf X rm -rf Y rm -rf Z..." for 100s of repetitions).
                // Cap output at a generous chars-per-second ratio for the audio
                // duration; a real fast speaker tops out around 17 chars/sec so
                // 40 leaves margin for noisy speech and abbreviations.
                let maxChars = max(160, Int(durationSec * 40.0))
                if raw.count > maxChars {
                    dlog("hallucination guard: \(raw.count) chars for \(durationSec)s audio (max \(maxChars)) — suppressing paste")
                    await MainActor.run {
                        self.state = .error
                        self.sound.play(.error)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.state = .idle
                        }
                    }
                    return
                }
                let postprocessStartedAt = Date()
                let processed = await MainActor.run {
                    PostProcessor(mode: mode).process(raw)
                }
                dlog("dictation timing postprocess=\(Self.elapsedString(since: postprocessStartedAt))s total=\(Self.elapsedString(since: pipelineStartedAt))s")

                // Verbatim modifier (Fn+Option) bypasses smart cleanup so the
                // raw transcribed text is pasted as-is. Setting `enabled: false`
                // also skips trigger phrases ("scratch that", "new paragraph"),
                // which is intentional — verbatim means literal.
                let verbatimMode = await MainActor.run { self.currentVerbatim }
                let cleanupEnabled = AppSettings.smartCleanupEnabled && !verbatimMode
                let cleaner = CleanupProcessor(
                    mode: mode,
                    enabled: cleanupEnabled,
                    llmCleaner: cleanupEnabled ? self.liveLLMCleaner : nil
                )
                let cleanupStartedAt = Date()
                let cleanedText = await cleaner.process(processed.text)
                let finalText = await MainActor.run {
                    guard cleanupEnabled else { return cleanedText }
                    return CleanupDictionaryProtection.apply(
                        cleanedText,
                        mode: mode,
                        entries: DictionaryStore.shared.entries
                    )
                }
                let cleanedMetrics = textLogMetrics(label: "cleaned", text: finalText)
                dlog("dictation timing cleanup=\(Self.elapsedString(since: cleanupStartedAt))s total=\(Self.elapsedString(since: pipelineStartedAt))s cleanup_enabled=\(cleanupEnabled) \(cleanedMetrics) verbatim=\(verbatimMode)")

                let wordCount = finalText.split(whereSeparator: { $0.isWhitespace }).count
                let model = AppSettings.transcriptionModel
                let cost = UsageTracker.costEstimate(durationSec: durationSec, model: model)
                UsageTracker.record(durationSec: durationSec, wordCount: wordCount, model: model)
                if !finalText.isEmpty {
                    let recorded = DictationHistoryStore.shared.record(DictationEntry(
                        mode: mode == .prose ? "prose" : "command",
                        durationSec: durationSec,
                        wordCount: wordCount,
                        text: finalText
                    ))
                    if !recorded {
                        dlog("dictation history record failed; paste will still proceed")
                    }
                }
                dlog("\(textLogMetrics(label: "processed", text: processed.text)) keys=\(processed.suffixKeys) final_words=\(wordCount) cost=$\(String(format: "%.4f", cost))")
                let pasteDelay: Double
                if finalText.isEmpty {
                    pasteDelay = 0
                    dlog("dictation timing paste_skipped total=\(Self.elapsedString(since: pipelineStartedAt))s")
                } else {
                    let pasteStartedAt = Date()
                    await self.pasteGate.run {
                        await self.injector.pasteAsync(
                            finalText,
                            keepOnClipboard: AppSettings.keepTranscriptionOnClipboard
                        )
                    }
                    dlog("dictation timing paste=\(Self.elapsedString(since: pasteStartedAt))s total=\(Self.elapsedString(since: pipelineStartedAt))s")
                    pasteDelay = 0.2
                }
                await MainActor.run {
                    for (i, key) in processed.suffixKeys.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + 0.18 * Double(i)) {
                            self.injector.sendKey(key)
                        }
                    }
                    self.state = .idle
                }
                dlog("dictation timing complete total=\(Self.elapsedString(since: pipelineStartedAt))s")
            } catch {
                dlog("transcription failed: \(error) total=\(Self.elapsedString(since: pipelineStartedAt))s")
                await MainActor.run {
                    self.state = .error
                    self.sound.play(.error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.state = .idle
                    }
                }
            }
        }
    }

    private func startPulsing() {
        guard pulseTimer == nil, let button = statusItem.button else { return }
        var dim = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak button] _ in
            guard let button else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                button.animator().alphaValue = dim ? 1.0 : 0.35
            }
            dim.toggle()
        }
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
    }

    private func wavStats(_ wav: Data) -> (durationSec: Double, rms: Double) {
        let headerSize = 44
        guard wav.count > headerSize else { return (0, 0) }
        let pcm = wav.subdata(in: headerSize..<wav.count)
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return (0, 0) }
        let duration = Double(sampleCount) / 16_000.0
        let rms = pcm.withUnsafeBytes { raw -> Double in
            let buf = raw.bindMemory(to: Int16.self)
            var sumSq = 0.0
            for s in buf { sumSq += Double(s) * Double(s) }
            return sqrt(sumSq / Double(buf.count))
        }
        return (duration, rms)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
