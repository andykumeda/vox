import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedMessage: String?
    @State private var keepOnClipboard: Bool = AppSettings.keepTranscriptionOnClipboard
    @State private var forceProse: Bool = AppSettings.forceProseMode
    @State private var model: TranscriptionModel = AppSettings.transcriptionModel
    @State private var totals: UsageTotals = UsageTracker.totals()
    let keychain: KeychainStore

    var body: some View {
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
                Toggle("Always use prose mode (ignore terminal detection)", isOn: Binding(
                    get: { forceProse },
                    set: { newValue in
                        forceProse = newValue
                        AppSettings.forceProseMode = newValue
                    }
                ))
                Text("Off: dictation in Terminal/iTerm/Wave/etc gets command formatting (no period, no caps, dash/NATO/control). On: always treat dictation as prose with sentence punctuation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 800)
        .onAppear {
            apiKey = keychain.read() ?? ""
            totals = UsageTracker.totals()
            model = AppSettings.transcriptionModel
            forceProse = AppSettings.forceProseMode
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
}

final class SettingsWindowController: NSWindowController {
    convenience init(keychain: KeychainStore) {
        let hosting = NSHostingController(rootView: SettingsView(keychain: keychain))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vox"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
