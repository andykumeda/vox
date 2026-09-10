import Foundation

public enum TranscriptionMode: String, Sendable {
    case prose
    case command

    public var whisperPrompt: String {
        switch self {
        case .prose:
            return "Transcribe the spoken English literally. Return only words supported by the audio, in the order spoken. Do not infer unstated facts, complete an implied thought, summarize, paraphrase, answer a question, or add a conclusion. Preserve the speaker's wording, uncertainty, false starts, repetitions, names, numbers, and sentence boundaries. Add punctuation only when supported by the speech; punctuation must not introduce or remove lexical content. Do not rewrite the speech as polished prose."
        case .command:
            return "Verbatim Unix shell commands fed directly into a terminal — never English prose. Examples of exact expected output: ls -l, ls -la, ls -lh, ls -a, cd .., cd -, rm -rf, rm -rf node_modules, cat README.md, cat foo.txt, grep -r foo, ps -ef, ps aux, df -h, du -sh, head -n 20, tail -f, chmod +x, chmod 755, mkdir -p, find . -name, git status, git log, git diff, docker ps, kubectl get pods, npm install, brew update, curl -sSL, ssh user@host. Never transcribe these as English words like 'hello', 'shall', 'shell', 'sell', 'cell', 'hey', 'how', 'lets', 'returned'. Single-letter flags are common: -l, -a, -r, -i, -v, -h, -n, -p, -f, -t, -u, -x. The user may say 'dash' or 'minus' for '-', NATO phonetic ('lima' for l, 'alpha' for a) for single letters, 'control C' for Ctrl+C, 'tab' for Tab, 'escape' for Esc. Always separate command from flags with one space (ls -l not ls-l). Do not capitalize. No trailing punctuation."
        }
    }
}
