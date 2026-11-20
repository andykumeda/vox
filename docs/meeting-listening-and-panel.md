# Listening-only recovery and automatic meeting controls

| Work | Owner | Acceptance | Status |
| --- | --- | --- | --- |
| Listening-only recovery | Recording | Recover the affected Mini transcript, preserve audio, and keep strong or recurring speech eligible for review. Verify the saved result and classifier controls. | Deployed |
| Automatic meeting controls | Panel | Show controls on a new meeting detection. Verify detection, panel behavior and user dismissal. | Deployed |
| Coordinated release | Integration | Verify Swift tests, dictation fixtures, installation, signed DMG and live update feed. | Deployed |


The older microphone check treated any speech confidence of 0.1 as a reason to
fail a meeting with an otherwise usable transcript. On a confirmed listening-only
recording, the revised on-device check accepted the microphone track. It rejected
a separately generated spoken control. An empty provider result with strong speech
or consecutive speech-leading windows still requires review. Missing classifier
results and incomplete analysis keep the prior protection. Audio from a meeting
completed using this check remains protected until explicit deletion.

The Mini logged Teams detection while recording with automatic controls enabled.
The detection handler discarded the event because it assumed recording implied a
visible panel. Detection now presents the controls unless the user dismissed them
during that recording.

The installed Mini app presented its panel in response to a synthetic native Webex
meeting window. WindowServer confirmed both windows were visible and the test app
kept focus. The test started no recording and restored the prior window state.
A focused AppKit test also showed the panel during a recording and verified that
closing it suppresses another presentation for the same recording. A real Teams
call after installation and a second-Mac update remain unverified.

## Delivery verification

Vox 0.7.95 build 119 was installed and restarted on the Mini. The operator
expired the retry cooldown on the affected record only. The production recovery
pipeline saved the completed transcript under its original meeting ID, generated
a summary, cleared the failure and warnings, and retained its audio. All three
decrypted source archives matched the SHA-256 digests taken before recovery.
No meeting content was added to the repository.

All 618 local Swift tests passed with SwiftPM's native build system. The
dictation regression passed seven fixtures with quality 1.0 and failure rate 0.
Strict codesign passed, and the mounted DMG executable and Info.plist matched the
installed copies. The public download matched the packaged DMG and verified
against the app's bundled Sparkle public key and the public feed's enclosure.

[Release v0.7.95](https://github.com/andykumeda/vox/releases/tag/v0.7.95)
is 2,876,834 bytes. SHA-256:
`1b8067362ab3b1e541749492d3e17e877f1a7b349e797d3ec25b07aeeda30c56`.
Pages deployment 44827081587 succeeded. Hosted Release Gate 44827059095 and
Dictation Regression 44827081868 were cancelled; the test results above are local.
