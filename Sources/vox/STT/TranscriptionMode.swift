import Foundation

public enum TranscriptionMode: String, Sendable {
    case prose
    case command

    public var whisperPrompt: String {
        switch self {
        case .prose:
            return "Standard English prose with natural punctuation. Use commas to join related clauses; prefer flowing sentences over short fragments. Use digits for dates, years, phone numbers, addresses, prices, times, measurements, and quantities of ten or more; spell out small whole numbers in ordinary prose. Preserve URLs, domains, and file names exactly (e.g., youtube.com, github.com/user/repo, README.md) without inserting spaces around the dot."
        case .command:
            return "Verbatim Unix shell commands. Output is fed straight into a terminal — never English prose. Short utterances like 'ls -l', 'cd ..', 'rm -rf', 'cat foo', 'ps -ef' are commands, not words; never transcribe them as 'hello', 'shall', 'let's', or similar. Single-letter flags are common: -l, -a, -r, -i, -v, -h, -n, -p, -f, -t, -u, -x. Always separate command from flags with a single space ('ls -l' not 'ls-l'). The user may say 'dash' or 'minus' for '-', and NATO phonetic ('lima' for L, 'alpha' for A, 'charlie' for C) for single letters. The user may say 'control C' for Ctrl+C, 'tab' for Tab, 'escape' for Esc. Common commands: sudo ls cd cat grep awk sed chmod ssh scp git docker kubectl npm brew wget curl head tail less rm cp mv mkdir find xargs ps top df du tar. Do not capitalize. No trailing punctuation."
        }
    }
}
