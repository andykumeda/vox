import Foundation

enum DictionaryDefaults {

    /// Built-in entries seeded on first launch. Each id is stable across
    /// versions; new app versions may append entries with new ids — never
    /// renumber existing ones.
    static let bundledDefaults: [DictionaryEntry] = [
        // Single-letter flag misfires: -<word> -> -l
        DictionaryEntry(id: "builtin-shell-l", spoken: "-shell", replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-shall-l", spoken: "-shall", replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-sell-l",  spoken: "-sell",  replacement: "-l",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-cell-l",  spoken: "-cell",  replacement: "-l",
                        mode: .command, isBuiltIn: true),
        // Single-letter flag misfires: -<word> -> -a
        DictionaryEntry(id: "builtin-hey-a",   spoken: "-hey",   replacement: "-a",
                        mode: .command, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hay-a",   spoken: "-hay",   replacement: "-a",
                        mode: .command, isBuiltIn: true),
        // Leading false-start before a dash flag -> "ls".
        DictionaryEntry(id: "builtin-hello-comma-ls", spoken: "hello,", replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hello-ls",       spoken: "hello",  replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hi-comma-ls",    spoken: "hi,",    replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hi-ls",          spoken: "hi",     replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hey-comma-ls",   spoken: "hey,",   replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
        DictionaryEntry(id: "builtin-hey-ls",         spoken: "hey",    replacement: "ls",
                        mode: .command, startsWith: true, isBuiltIn: true),
    ]
}
