import Foundation

public enum DictionaryMatcher {

    /// Apply all enabled entries (matching `scope`) to `input`, returning
    /// the rewritten string. Pure function — no I/O.
    public static func apply(
        entries: [DictionaryEntry],
        to input: String,
        scope: Scope
    ) -> String {
        guard !input.isEmpty else { return input }
        let active = entries.filter { e in
            e.enabled && (e.mode == scope || e.mode == .both)
        }
        guard !active.isEmpty else { return input }

        // Longer-spoken wins. Tokenize spoken once per entry; strip edge punct
        // from each spoken token so an entry like spoken="hello," still matches
        // its core "hello" against either "hello" or "hello," in the input.
        let prepared: [(entry: DictionaryEntry, spokenTokens: [String])] =
            active.map { ($0, tokenize($0.spoken).map(stripEdgePunct)) }
                .filter { !$0.1.isEmpty && !$0.1.contains(where: { $0.isEmpty }) }
                .sorted { $0.1.count > $1.1.count }

        var tokens = tokenize(input)
        for (e, sp) in prepared {
            tokens = replace(in: tokens, spoken: sp, entry: e)
        }
        // Whitespace normalization is intentional: a side effect of token
        // round-tripping. Multi-space input becomes single-space output.
        return tokens.joined(separator: " ")
    }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// True for sentence-edge punctuation that may be attached to a word token
    /// after Whisper transcription. Letters, numbers, and internal apostrophes
    /// or hyphens are preserved as part of the token core.
    private static func isEdgePunct(_ c: Character) -> Bool {
        switch c {
        case ",", ".", ";", ":", "!", "?",
             "(", ")", "[", "]", "{", "}",
             "\"", "“", "”", "‘", "’":
            return true
        default:
            return false
        }
    }

    private static func stripEdgePunct(_ s: String) -> String {
        var start = s.startIndex
        while start < s.endIndex, isEdgePunct(s[start]) { start = s.index(after: start) }
        var end = s.endIndex
        while end > start {
            let prev = s.index(before: end)
            if isEdgePunct(s[prev]) { end = prev } else { break }
        }
        return String(s[start..<end])
    }

    private static func leadingPunct(_ s: String) -> String {
        var idx = s.startIndex
        while idx < s.endIndex, isEdgePunct(s[idx]) { idx = s.index(after: idx) }
        return String(s[s.startIndex..<idx])
    }

    private static func trailingPunct(_ s: String) -> String {
        var idx = s.endIndex
        while idx > s.startIndex {
            let prev = s.index(before: idx)
            if isEdgePunct(s[prev]) { idx = prev } else { break }
        }
        return String(s[idx..<s.endIndex])
    }

    private static func valuesEqual(_ a: String, _ b: String, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            return a.compare(b, options: .caseInsensitive) == .orderedSame
        }
        return a == b
    }

    private static func possessiveSuffix(
        _ token: String,
        spoken: String,
        caseInsensitive: Bool
    ) -> String? {
        let core = stripEdgePunct(token)
        for suffix in ["'s", "’s", "'S", "’S"] where core.hasSuffix(suffix) {
            let base = String(core.dropLast(suffix.count))
            if valuesEqual(base, spoken, caseInsensitive: caseInsensitive) {
                return suffix
            }
        }
        return nil
    }

    private static func tokensEqual(_ a: String, _ b: String, caseInsensitive: Bool) -> Bool {
        // Compare against the *core* of the input token so punctuation attached
        // by Whisper (e.g. "Andie," after a sentence-internal comma) doesn't
        // defeat dictionary matching. The dictionary's spoken pattern is
        // assumed to have no edge punctuation.
        let core = stripEdgePunct(a)
        if valuesEqual(core, b, caseInsensitive: caseInsensitive) {
            return true
        }
        return possessiveSuffix(a, spoken: b, caseInsensitive: caseInsensitive) != nil
    }

    private static func replace(
        in input: [String],
        spoken: [String],
        entry: DictionaryEntry
    ) -> [String] {
        let n = input.count
        let k = spoken.count
        guard k > 0, k <= n else { return input }
        let replacement = tokenize(entry.replacement)

        func windowMatches(at i: Int) -> Bool {
            guard i + k <= n else { return false }
            for j in 0..<k {
                if !tokensEqual(input[i + j], spoken[j], caseInsensitive: entry.caseInsensitive) {
                    return false
                }
            }
            return true
        }

        if entry.startsWith {
            // Only one possible match site: index 0.
            if windowMatches(at: 0) {
                return replacement + Array(input[k...])
            }
            return input
        }

        var out: [String] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            if windowMatches(at: i) {
                // Preserve any leading punct from the first input token and
                // trailing punct from the last input token in the matched
                // window. Without this, "Andie," (with attached comma) would
                // be replaced by just "Andy", losing the comma.
                let leading = Self.leadingPunct(input[i])
                let trailing = Self.trailingPunct(input[i + k - 1])
                let possessive = Self.possessiveSuffix(
                    input[i + k - 1],
                    spoken: spoken[k - 1],
                    caseInsensitive: entry.caseInsensitive
                ) ?? ""
                if replacement.isEmpty {
                    // Empty replacement = deletion entry (e.g. "um" → "").
                    // Drop the punct too — keeping a stranded comma would be
                    // worse than the silent deletion.
                } else {
                    var rep = replacement
                    if !leading.isEmpty {
                        rep[0] = leading + rep[0]
                    }
                    if !possessive.isEmpty {
                        rep[rep.count - 1] = rep[rep.count - 1] + possessive
                    }
                    if !trailing.isEmpty {
                        rep[rep.count - 1] = rep[rep.count - 1] + trailing
                    }
                    out.append(contentsOf: rep)
                }
                i += k
            } else {
                out.append(input[i])
                i += 1
            }
        }
        return out
    }
}
