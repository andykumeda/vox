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
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        attributed = renderMarkdown(raw)
    }

    /// Foundation's `AttributedString(markdown:)` only handles inline syntax.
    /// Render headers / lists / fenced code blocks ourselves; run inline
    /// markdown on each line so `**bold**` and `` `code` `` still resolve.
    private func renderMarkdown(_ raw: String) -> AttributedString {
        var result = AttributedString()
        var inCode = false
        var codeBuf = ""

        func renderInline(_ s: String) -> AttributedString {
            (try? AttributedString(
                markdown: s,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(s)
        }

        for rawLine in raw.components(separatedBy: "\n") {
            if rawLine.hasPrefix("```") {
                if inCode {
                    var code = AttributedString(codeBuf.trimmingCharacters(in: .newlines) + "\n\n")
                    code.font = .system(.callout, design: .monospaced)
                    code.foregroundColor = .secondary
                    result.append(code)
                    codeBuf = ""
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuf += rawLine + "\n"
                continue
            }

            var line = rawLine
            var size: CGFloat?
            if line.hasPrefix("# ")   { line = String(line.dropFirst(2)); size = 22 }
            else if line.hasPrefix("## ")  { line = String(line.dropFirst(3)); size = 17 }
            else if line.hasPrefix("### ") { line = String(line.dropFirst(4)); size = 14 }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "  • " + String(line.dropFirst(2))
            }

            var attr = renderInline(line)
            if let size {
                attr.font = .system(size: size, weight: .semibold)
            }
            attr.append(AttributedString("\n"))
            result.append(attr)
        }
        return result
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
