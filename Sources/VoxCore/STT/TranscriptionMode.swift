import Foundation

public enum TranscriptionMode: String, Sendable {
    case prose
    case command

    public var whisperPrompt: String {
        switch self {
        case .prose:
            return "Standard English prose with natural punctuation. Break independent clauses into separate sentences with periods. Avoid long comma-chained sentences; do not stitch multiple complete thoughts together with commas. Reserve commas for short parenthetical phrases, list items, or before a single coordinator inside one clause. Always use digits for times, prices, measurements, and option labels — never spell them out (5 hours, $5, 1 TB, 3%, 9 a.m., option 1). Prefer currency symbols and standard unit abbreviations when the speaker says dollars, cents, kilobytes, megabytes, gigabytes, or terabytes. Use digits for dates, years, phone numbers, addresses, and quantities of ten or more. Spell out small whole numbers only in ordinary non-quantitative prose (e.g., three apples). Never spell a number as separate letters (F-I-F-T-Y); transcribe it as digits. Preserve URLs, domains, and file names exactly (e.g., youtube.com, github.com/user/repo, README.md) without inserting spaces around the dot."
        case .command:
            return "Verbatim Unix shell commands fed directly into a terminal — never English prose. Examples of exact expected output: ls -l, ls -la, ls -lh, ls -a, cd .., cd -, rm -rf, rm -rf node_modules, cat README.md, cat foo.txt, grep -r foo, ps -ef, ps aux, df -h, du -sh, head -n 20, tail -f, chmod +x, chmod 755, mkdir -p, find . -name, git status, git log, git diff, docker ps, kubectl get pods, npm install, brew update, curl -sSL, ssh user@host. Never transcribe these as English words like 'hello', 'shall', 'shell', 'sell', 'cell', 'hey', 'how', 'lets', 'returned'. Single-letter flags are common: -l, -a, -r, -i, -v, -h, -n, -p, -f, -t, -u, -x. The user may say 'dash' or 'minus' for '-', NATO phonetic ('lima' for l, 'alpha' for a) for single letters, 'control C' for Ctrl+C, 'tab' for Tab, 'escape' for Esc. Always separate command from flags with one space (ls -l not ls-l). Do not capitalize. No trailing punctuation."
        }
    }
}
