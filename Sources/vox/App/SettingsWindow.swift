import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedMessage: String?
    @State private var keepOnClipboard: Bool = AppSettings.keepTranscriptionOnClipboard
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
        .frame(width: 460, height: 460)
        .onAppear {
            apiKey = keychain.read() ?? ""
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
