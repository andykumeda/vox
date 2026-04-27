import AppKit
import SwiftUI

struct HelpView: View {
    @State private var attributed: AttributedString?

    var body: some View {
        ScrollView {
            if let s = attributed {
                Text(s)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("Help unavailable.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(width: 640, height: 720)
        .onAppear { loadHelp() }
    }

    private func loadHelp() {
        guard let url = Bundle.main.url(forResource: "help", withExtension: "md"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else { return }
        attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
    }
}

public final class HelpWindowController {
    private var window: NSWindow?

    public init() {}

    @MainActor
    public func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: HelpView())
        let w = NSWindow(contentViewController: hosting)
        w.title = "Vox Help"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.minSize = NSSize(width: 480, height: 400)
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
