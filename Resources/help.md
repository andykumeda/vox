# Vox — Quick Help

## Recording
Hold **Fn** (default) and speak. Release to transcribe.
Switch trigger to **tap-to-toggle** in Settings → Hotkeys if you prefer one-tap-start, one-tap-stop.

## Modes
- **Prose** — natural sentences, capitalized, with terminal punctuation. Default for most apps.
- **Command** — verbatim shell commands, no capitalization, no trailing punctuation. Auto-selected when the focused app is a terminal (Terminal, iTerm, Wave, etc.).
Press your **Mode toggle** hotkey (default `⌃⌥M`) to force prose regardless of focus. The menu-bar icon shows a lock when prose is forced.

## Dictionary
Settings → Dictionary lets you define custom substitutions:
- Spoken `vox` → replacement `Vox` (proper-noun fix in prose).
- Spoken `next field` → replacement `next tab` to insert "next" + Tab key.
- Mode scope: command, prose, or both.
- "Match only at start" anchors to the first word of an utterance.
12 built-in fixups are active behind the scenes (e.g., `ls -shell` → `ls -l`). To silence one, click **Reveal in Finder**, open `dictionary.json`, set `"enabled": false`, save. The change reloads automatically.

## Key-press substitutions
A replacement that ends with one of these words fires that key after pasting:
- `tab` — Tab (needs at least one preceding word)
- `return`, `enter`, `newline` — Return
- `escape`, `esc` — Esc
- `control X` — Ctrl+X (any letter)

## Hotkeys
Settings → Hotkeys lets you rebind:
- **Record dictation** (default Fn, press-and-hold).
- **Toggle mode** (default `⌃⌥M`, tap).
- **Paste keystroke** (default `⌘V`, sent to the focused app to inject text).

## Files
- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Logs: `~/Library/Logs/vox.log`

## Troubleshooting
- **Paste fails silently** — make sure Vox launched via `open dist/Vox.app`, not the binary directly. TCC attributes Accessibility permissions to the launching process.
- **Fn key doesn't fire** — System Settings → Keyboard → "Press 🌐 key to" must be **Do Nothing**.
- **Wrong transcription on short phrases** — add a Dictionary entry to fix the specific misfire (e.g., spoken `-shell` → `-l`).
