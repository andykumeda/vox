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

        // Longer-spoken wins. Tokenize spoken once per entry for sort + match.
        let prepared: [(entry: DictionaryEntry, spokenTokens: [String])] =
            active.map { ($0, tokenize($0.spoken)) }
                .filter { !$0.1.isEmpty }
                .sorted { $0.1.count > $1.1.count }

        var tokens = tokenize(input)
        for (e, sp) in prepared {
            tokens = replace(in: tokens, spoken: sp, entry: e)
        }
        return tokens.joined(separator: " ")
    }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func tokensEqual(_ a: String, _ b: String, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            return a.compare(b, options: .caseInsensitive) == .orderedSame
        }
        return a == b
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
                out.append(contentsOf: replacement)
                i += k
            } else {
                out.append(input[i])
                i += 1
            }
        }
        return out
    }
}
