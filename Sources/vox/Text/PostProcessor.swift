import Foundation

public struct PostProcessor {
    public let mode: TranscriptionMode
    private let numberNormalizer = NumberNormalizer()
    private let dictionaryProvider: () -> [DictionaryEntry]

    public init(
        mode: TranscriptionMode,
        dictionaryProvider: @escaping () -> [DictionaryEntry] = {
            MainActor.assumeIsolated { DictionaryStore.shared.entries }
        }
    ) {
        self.mode = mode
        self.dictionaryProvider = dictionaryProvider
    }

    public func apply(_ raw: String) -> String {
        return process(raw).text
    }

    public func process(_ raw: String) -> (text: String, suffixKeys: [SuffixKey]) {
        var s = raw

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = collapseInternalWhitespace(s)
        s = numberNormalizer.normalize(s, aggressive: mode == .command)

        // Shield URLs, domains, IPs, version strings, and common file names from
        // sentence-splitting + capitalization so "youtube.com" doesn't become
        // "Youtube. Com." after post-processing.
        let (shielded, urlMap) = shieldURLs(s)
        s = shielded

        s = ensureSpaceAfterSentenceEnd(s)

        var suffixKeys: [SuffixKey] = []
        switch mode {
        case .prose:
            s = capitalizeSentenceStarts(s)
            s = ensureTrailingTerminator(s)
            s = applyDictionary(.prose, s)
            // Send a Space keystroke after paste instead of appending " " to
            // the text. Some apps (notably Wave terminal) strip trailing
            // whitespace from pasted content; a discrete keystroke can't be
            // stripped that way.
            suffixKeys = [.space]
        case .command:
            s = lowercaseFirstLetter(s)
            s = stripTrailingSentencePunctuation(s)
            s = expandSpokenPunctuation(s)
            s = splitCommandFromFlag(s)
            s = applyDictionary(.command, s)
            let extracted = extractTrailingSuffixKeys(s)
            s = extracted.text
            suffixKeys = extracted.keys
            // If no other keys were extracted and we did paste something, send
            // a Space keystroke so back-to-back command-mode dictations are
            // separated. Skipped when tab/return/escape/control was already
            // attached (those have specific semantics that shouldn't get an
            // extra space prefix).
            if suffixKeys.isEmpty && !s.isEmpty {
                suffixKeys = [.space]
            }
        }

        return (restoreURLs(s, urlMap), suffixKeys)
    }

    // Words that, when first in a sentence, signal a question. Used to choose
    // "?" over "." when Whisper omits the terminator.
    private static let questionStarters: Set<String> = [
        "is", "are", "was", "were", "am", "do", "does", "did", "have",
        "has", "had", "will", "would", "should", "shall", "can", "could",
        "may", "might", "must", "who", "what", "when", "where", "why",
        "how", "whose", "which",
    ]

    // Prose mode: guarantee output ends with . ! or ?. Detect question-shaped
    // sentences ("Is it raining" → "?", not ".") so the user doesn't have to
    // dictate the question mark.
    private func ensureTrailingTerminator(_ input: String) -> String {
        guard let last = input.last else { return input }
        if last == "." || last == "!" || last == "?" { return input }
        // Find the start of the final sentence (after the last . ! ?).
        let chars = Array(input)
        var sentenceStart = 0
        for i in (0..<chars.count).reversed() {
            if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                sentenceStart = i + 1
                break
            }
        }
        let lastSentence = String(chars[sentenceStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = lastSentence
            .split(whereSeparator: { !$0.isLetter })
            .first
            .map { String($0).lowercased() } ?? ""
        let terminator = Self.questionStarters.contains(firstWord) ? "?" : "."
        return input + terminator
    }

    // Collapse runs of internal whitespace to a single space. Keep newlines intact.
    private func collapseInternalWhitespace(_ input: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in input {
            if ch == " " || ch == "\t" {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    // Ensure exactly one space after . ! ? when followed by a non-whitespace character.
    private func ensureSpaceAfterSentenceEnd(_ input: String) -> String {
        var out = ""
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            out.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if let n = next, !n.isWhitespace {
                    out.append(" ")
                }
            }
            i += 1
        }
        return out
    }

    private func capitalizeSentenceStarts(_ input: String) -> String {
        var chars = Array(input)
        var capitalizeNext = true
        for i in chars.indices {
            let ch = chars[i]
            if ch.isLetter {
                if capitalizeNext {
                    chars[i] = Character(ch.uppercased())
                    capitalizeNext = false
                }
            } else if ch == "." || ch == "!" || ch == "?" {
                capitalizeNext = true
            } else if !ch.isWhitespace {
                capitalizeNext = false
            }
        }
        return String(chars)
    }

    private func lowercaseFirstLetter(_ input: String) -> String {
        guard let first = input.first, first.isLetter, first.isUppercase else { return input }
        return first.lowercased() + input.dropFirst()
    }

    private func stripTrailingSentencePunctuation(_ input: String) -> String {
        var s = input
        while let last = s.last, last == "." || last == "!" || last == "?" || last.isWhitespace {
            s.removeLast()
        }
        return s
    }

    // MARK: - Command / flag splitting

    // Commands where `<cmd>-<suffix>` is almost never a real binary — safe
    // to split "<cmd>-<flag>" back into "<cmd> -<flag>". Deliberately
    // excludes ssh/scp (ssh-keygen, ssh-add), git/docker/kubectl (subcommand
    // aliases), make/npm/brew (plugin forms) to avoid rewriting valid names.
    private static let splittableCommands: [String] = [
        "ls", "cd", "cat", "grep", "awk", "sed", "chmod", "chown", "rm", "cp",
        "mv", "mkdir", "rmdir", "touch", "echo", "find", "man", "ps", "kill",
        "top", "df", "du", "tar", "zip", "unzip", "head", "tail", "less",
        "more", "which", "sort", "uniq", "wc", "xargs", "cut", "tr", "diff",
        "tee", "file", "stat", "ln", "ping", "lsof", "curl", "wget",
    ]

    private static let splitRegex: NSRegularExpression? = {
        let pattern = "\\b(" + splittableCommands.joined(separator: "|") + ")-(?=[a-zA-Z])"
        return try? NSRegularExpression(pattern: pattern)
    }()

    private func splitCommandFromFlag(_ input: String) -> String {
        guard let re = Self.splitRegex else { return input }
        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        return re.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "$1 -")
    }

    // MARK: - User dictionary

    private func applyDictionary(_ scope: Scope, _ input: String) -> String {
        DictionaryMatcher.apply(entries: dictionaryProvider(), to: input, scope: scope)
    }

    // MARK: - Spoken punctuation (command mode)

    // Whisper transcribes shell punctuation as words. Convert in command mode:
    // "head dash n three" → "head -n 3", "config dot json" → "config.json".
    // Order matters: "double dash" before "dash" to win the alternation.
    private static let spokenPunctReplacements: [(pattern: String, replacement: String)] = [
        ("\\bdouble dash\\b", "--"),
        ("\\bdouble minus\\b", "--"),
        ("\\bdash\\b", "-"),
        ("\\bminus\\b", "-"),
        ("\\bpipe\\b", "|"),
        ("\\bdot\\b", "."),
    ]

    // NATO phonetic alphabet → single letter. Only expanded when immediately
    // following a "-" or "--" (so "ls dash lima" → "ls -l", but "echo lima"
    // stays literal — "echo" is a real shell command, "lima" could be content).
    private static let natoPhonetic: [String: String] = [
        "alpha": "a", "bravo": "b", "charlie": "c", "delta": "d",
        "echo": "e", "foxtrot": "f", "golf": "g", "hotel": "h",
        "india": "i", "juliet": "j", "juliett": "j", "kilo": "k",
        "lima": "l", "mike": "m", "november": "n", "oscar": "o",
        "papa": "p", "quebec": "q", "romeo": "r", "sierra": "s",
        "tango": "t", "uniform": "u", "victor": "v", "whiskey": "w",
        "xray": "x", "x-ray": "x", "yankee": "y", "zulu": "z",
    ]

    private func expandSpokenPunctuation(_ input: String) -> String {
        var s = input
        for (pat, repl) in Self.spokenPunctReplacements {
            if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let ns = s as NSString
                s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: repl)
            }
        }
        // Expand NATO phonetic words that follow "-" or "--" (one or more in a
        // row, so "rm minus romeo foxtrot" → "rm -rf"). Pattern captures the
        // dash and all consecutive NATO words.
        let natoAlt = Self.natoPhonetic.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let re = try? NSRegularExpression(pattern: "(--?)((?:\\s+(?:\(natoAlt)))+)\\b", options: [.caseInsensitive]) {
            let ns = s as NSString
            let matches = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let dashes = ns.substring(with: m.range(at: 1))
                let chunk = ns.substring(with: m.range(at: 2))
                let letters = chunk.split(whereSeparator: { $0.isWhitespace })
                    .compactMap { Self.natoPhonetic[$0.lowercased()] }
                    .joined()
                s = (s as NSString).replacingCharacters(in: m.range, with: dashes + letters)
            }
        }
        // Glue "- x" → "-x" so "head - n" becomes "head -n", same for "-- name".
        if let re = try? NSRegularExpression(pattern: "(--?)\\s+([a-zA-Z0-9])") {
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2")
        }
        // Glue "word . word" → "word.word" so "readme dot md" becomes "readme.md".
        // Slash deliberately omitted — "cd slash usr slash local" is genuinely
        // ambiguous (path arg vs internal path glue). Dictate "/" literally.
        if let re = try? NSRegularExpression(pattern: "([a-zA-Z0-9])\\s*\\.\\s*([a-zA-Z0-9])") {
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "$1.$2")
        }
        return s
    }

    // MARK: - Trailing key suffix (command mode)

    // Spoken keywords at end of dictation map to a synthesized key event after
    // paste. Lets the user say "brew upd tab" → pastes "brew upd" then sends
    // Tab so the shell completes "update". Only stripped when not the lone
    // word — bare "tab" stays as text.
    // `requiresPrefix=true` means the keyword must follow other text — bare
    // "tab" stays as literal text (could be filename or argument). Return /
    // enter / escape always fire even when said alone (common: just hit Enter).
    private static let suffixKeyMap: [(word: String, key: SuffixKey, requiresPrefix: Bool)] = [
        ("tab", .tab, true),
        ("return", .return, false),
        ("enter", .return, false),
        ("newline", .return, false),
        ("escape", .escape, false),
        ("esc", .escape, false),
    ]

    private func extractTrailingSuffixKeys(_ input: String) -> (text: String, keys: [SuffixKey]) {
        var s = input
        var keys: [SuffixKey] = []
        while true {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let last = parts.last else { break }
            let lower = last.lowercased()
            // Two-word "control X" / "ctrl X" → Ctrl+letter
            if parts.count >= 2, lower.count == 1, lower.first?.isLetter == true {
                let secondLast = parts[parts.count - 2].lowercased()
                if secondLast == "control" || secondLast == "ctrl" {
                    keys.insert(.control(lower.first!), at: 0)
                    s = parts.dropLast(2).joined(separator: " ")
                    continue
                }
            }
            // Single-word tab/return/enter/newline/escape/esc.
            if let entry = Self.suffixKeyMap.first(where: { $0.word == lower }),
               !(entry.requiresPrefix && parts.count < 2) {
                keys.insert(entry.key, at: 0)
                s = parts.dropLast(1).joined(separator: " ")
                continue
            }
            break
        }
        return (s, keys)
    }

    // MARK: - URL / filename shielding

    // Private-Use-Area markers — unlikely to collide with any speech output.
    private static let shieldOpen = "\u{E000}"
    private static let shieldClose = "\u{E001}"

    private static let shieldRegex: NSRegularExpression? = {
        // Ordered alternation: explicit schemes first, then bare domains,
        // IPs, versions, file names.
        let tlds = "com|org|net|io|dev|app|co|edu|gov|uk|us|me|ai|xyz|site|tech|blog|news|info|biz|cloud|tv|fm|jp|de|fr|ca|eu|sh|re|to|ly"
        let exts = "txt|md|pdf|swift|js|ts|tsx|jsx|json|yaml|yml|sh|zsh|bash|log|py|rb|rs|go|java|cpp|c|h|hpp|html|css|scss|png|jpg|jpeg|gif|svg|mp3|mp4|wav|zip|tar|gz|csv|xml|toml"
        // TLDs and file extensions are intentionally lowercase-only (no
        // caseInsensitive flag). Whisper capitalizes sentence starts, so
        // "Sentence one. Org members arrived." would otherwise false-match
        // "one. Org" as a domain. URLs/filenames almost always appear in
        // lowercase — accept the rare "PHOTO.JPG" miss to avoid that.
        let parts = [
            "https?://[^\\s]+",
            "\\b[a-zA-Z0-9][a-zA-Z0-9-]*\\.(?:\(tlds))(?:\\.[a-z]{2,})?(?:/[^\\s]*)?\\b",
            "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b",
            "\\bv\\d+(?:\\.\\d+)+\\b",
            // Compound archive extensions (listed before simple to win alternation).
            "\\b[a-zA-Z0-9_-]+\\.tar\\.(?:gz|bz2|xz|zst)\\b",
            "\\b[a-zA-Z0-9_-]+\\.(?:\(exts))\\b",
        ]
        let pattern = parts.joined(separator: "|")
        return try? NSRegularExpression(pattern: pattern)
    }()

    private func shieldURLs(_ input: String) -> (String, [(String, String)]) {
        guard let re = Self.shieldRegex else { return (input, []) }
        let nsInput = input as NSString
        let matches = re.matches(in: input, options: [], range: NSRange(location: 0, length: nsInput.length))
        guard !matches.isEmpty else { return (input, []) }

        var map: [(String, String)] = []
        var result = nsInput.copy() as! NSString
        for (i, m) in matches.enumerated().reversed() {
            let original = nsInput.substring(with: m.range)
            let token = "\(Self.shieldOpen)\(i)\(Self.shieldClose)"
            map.append((token, original))
            result = result.replacingCharacters(in: m.range, with: token) as NSString
        }
        return (result as String, map)
    }

    private func restoreURLs(_ input: String, _ map: [(String, String)]) -> String {
        var result = input
        for (token, original) in map {
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }
}
