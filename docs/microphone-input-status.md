# Automatic built-in microphone display — 2026-10-11

When the preferred USB microphone is unplugged, Settings now shows the active built-in microphone as “automatic” in its Input picker. Active-input, menu, and tooltip labels present this as normal operation. Vox retains the preferred USB selection so plugging it back in restores it automatically. An unavailable-input warning remains when no built-in fallback is active.

The reported disconnect was a presentation issue: device-route metadata confirmed that unplugging the USB microphone already restored the built-in input. Audio device selection and recording behavior are unchanged.

| Workstream | Owner | Acceptance | State |
| --- | --- | --- | --- |
| Fallback presentation | Codex | Built-in active input appears in the picker and menu without a disconnected warning; saved preference retained | Verified |
| Production and Sparkle | Codex | Unique 0.7.75 / 99 bundle installed, signed DMG published, live feed verified | Deployed |
| Rendered Settings smoke | User | With Settings open, unplug USB mic and verify built-in “automatic”; reconnect and verify preferred input returns | Not started |

Changed modules: SettingsWindow and MenuBarController. README and Help explain the Input picker. No operational policies or provider settings changed.

Verification: 496 macOS and 17 VoxCore tests pass. Existing route tests cover automatic built-in fallback and preferred-device return without changing the saved selection. New label-only tests were not added. Seven dictation fixtures pass (quality 1.0, failure rate 0.0). `git diff --check`, strict bundle signing, and DMG verification pass. Installed and packaged executable SHA-256 match. Production 0.7.75 / 99 is installed and restarted; Sparkle publication is verified. Native UI inspection timed out, so rendered-label confirmation remains pending.

Release: source `dedbbcb`, appcast `7451ee3`, tag/release `v0.7.75`. Public DMG SHA-256: `21f85a6f569f07878bc09166f516532bbddce8cba4346d5ce256f5b94187a4ca`. Raw/live Sparkle feed verify version 0.7.75 / 99, URL, signature, and 2,737,712-byte length. Anonymous download matches the package; bundled-key Ed25519 verification passes. The downloaded DMG was mounted read-only and its version/build, strict bundle signature, and updated Help verified. Release Gate, source Dictation Regression, and Pages deployment passed. Production startup confirms microphone permission, hotkey, and Accessibility. Manual rendered Settings/menu labels and spoken dictation after updating remain pending.
