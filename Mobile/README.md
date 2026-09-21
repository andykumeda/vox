# Vox for iPhone MVP

This experimental iOS 18+ project contains a host app and custom keyboard
extension. The scope is personal / TestFlight use with a bring-your-own OpenAI
key. Accounts, sync, billing, meetings, and Android are outside this MVP.

The host app owns microphone capture, OpenAI access, cleanup, dictionary, and
history. The keyboard provides basic QWERTY input and exchanges request state
and completed text through the App Group container. The exact Apple Notes
initiation → record → stop → one-time insertion flow remains unverified on a
physical iPhone; a successful build does not satisfy that gate.

## Build and install

1. Open `Mobile/VoxMobile.xcodeproj` from the repository root in Xcode 27.
   The current App Intent source uses iOS 27 SDK declarations, even though the
   runtime deployment target is iOS 18.
2. Select an Apple Development team for both targets.
3. Confirm these identifiers exist for that team:
   - `com.andykumeda.vox.ios`
   - `com.andykumeda.vox.ios.keyboard`
   - App Group `group.com.andykumeda.vox`
4. Run the `VoxMobile` scheme on an iPhone running iOS 18 or later.
5. Open Vox once, enter an OpenAI API key, and grant microphone access.
6. In iPhone Settings → General → Keyboard → Keyboards, add **Vox Keyboard**
   and enable **Allow Full Access** for dictation handoff.

For a compile check from the repository root, without device signing:

```sh
xcodebuild -project Mobile/VoxMobile.xcodeproj -scheme VoxMobile \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The project consumes `Sources/VoxCore` as a local Swift package. Root-level
`swift test` covers the portable pipeline and exchange state machine; it does
not run the iPhone app or keyboard.

## Keyboard handoff to validate

1. In an editable Notes field, select Vox Keyboard and tap its microphone.
2. The keyboard requests `vox://dictate?id=…`. If iOS does not open Vox,
   manually open it; the host resumes the pending request.
3. After Vox starts recording, return to Notes, speak, and tap **Stop** in
   Vox Keyboard.
4. The host transcribes in the background. The visible keyboard consumes only
   the matching ready request and inserts its text once.

The host uses `gpt-4o-transcribe` and prose mode. Its Smart Cleanup toggle is
on by default; custom dictionary entries and encrypted raw/final history are
managed in the host app. No macOS credentials or preferences are synced.

The keyboard rejects results more than two minutes after the request was
created, including recording and processing time. This is not a two-minute
window beginning when transcription finishes. Expiry is checked when a visible
keyboard handles a ready result; it is not a background file-deletion timer.

Custom keyboards cannot capture microphone audio themselves. Secure fields
can replace third-party keyboards, and some apps disable them entirely. Full
Access enables the App Group handoff; the keyboard does not receive the OpenAI
credential or perform transcription requests.

## Experimental App Intent

`VoxRecordingIntent.swift` also exposes **Toggle Vox Dictation** through App
Intents/Shortcuts with a Live Activity. This is a separate feasibility path,
not a verified replacement for the keyboard handoff. It uses its own recorder
and the shared prose pipeline with Smart Cleanup disabled; it currently does
not apply host dictionary entries or save host history. Do not mix this trigger
with an active host-app recording. Its initiation and stop behavior must be
proven on the physical device before treating it as usable from Notes.

## Local data

The App Group is `group.com.andykumeda.vox`:

- `dictation-exchange.json` stores request state and the pending result as
  ordinary JSON. Consuming, cancelling, or replacing the request clears that
  result; transcript-history encryption does not cover this handoff file.
- `History/history.json` contains an encrypted transcript envelope despite its
  filename. The encryption key and OpenAI key live in the host's Keychain.
- `Dictionary/dictionary.json` stores plain-text dictionary entries.
- `Recordings/` holds temporary WAVs, removed after processing or cancellation.

## Known lifecycle gaps

Source review found two unresolved cases; they were not physically reproduced
in this audit. Cancelling from the keyboard updates the shared request state,
but the host poller handles stop requests only, so this does not immediately
stop an active host microphone recording. Stop recording in Vox itself when
needed. The experimental App Intent can reset another active exchange and owns
a separate recorder, so mixing it with host recording bypasses the normal
active-request guard. Resolve and test both before broader use.

Audio is sent to OpenAI. The host's optional Smart Cleanup also sends text to
OpenAI. Local encryption does not change the provider's retention behavior.

## Required physical-device checks

Start with the shortest decisive Notes test on an unlocked iPhone: invoke the
chosen trigger, speak a known sentence, stop, and verify that exact text appears
once in the original field. Record the device, iOS version, trigger, and result
in `HANDOFF.md` before expanding the MVP.

Then verify cancellation, a second consecutive dictation, expired/stale
requests, keyboard dismissal/reopening, switching fields, loss of network,
background-task expiration, Full Access disabled, and a secure field. Confirm
that each failure preserves existing text and does not insert an older result.
Build success, a state-machine unit test, or installation alone cannot replace
these checks.
