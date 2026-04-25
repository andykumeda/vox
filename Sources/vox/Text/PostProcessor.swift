import Foundation

public struct PostProcessor {
    public let mode: TranscriptionMode
    private let numberNormalizer = NumberNormalizer()

    public init(mode: TranscriptionMode) {
        self.mode = mode
    }

    public func apply(_ raw: String) -> String {
        var s = raw

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = collapseInternalWhitespace(s)
        s = numberNormalizer.normalize(s)

        // Shield URLs, domains, IPs, version strings, and common file names from
        // sentence-splitting + capitalization so "youtube.com" doesn't become
        // "Youtube. Com." after post-processing.
        let (shielded, urlMap) = shieldURLs(s)
        s = shielded

        s = ensureSpaceAfterSentenceEnd(s)

        switch mode {
        case .prose:
            s = capitalizeSentenceStarts(s)
            s = ensureTrailingTerminator(s)
            s = s + " "
        case .command:
            s = lowercaseFirstLetter(s)
            s = stripTrailingSentencePunctuation(s)
        }

        return restoreURLs(s, urlMap)
    }

    // Prose mode: guarantee output ends with . ! or ? so the next dictation starts a new sentence.
    private func ensureTrailingTerminator(_ input: String) -> String {
        guard let last = input.last else { return input }
        if last == "." || last == "!" || last == "?" { return input }
        return input + "."
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
