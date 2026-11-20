# Listening-only recovery and automatic meeting controls

| Work | Owner | Acceptance | Status |
| --- | --- | --- | --- |
| Listening-only recovery | Recording | Recover the affected Mini transcript, preserve audio, and keep strong or recurring speech eligible for review. Verify the saved result and classifier controls. | In progress |
| Automatic meeting controls | Panel | Show controls on a new meeting detection. Verify detection, panel behavior and user dismissal. | Verified |
| Coordinated release | Integration | Verify Swift tests, dictation fixtures, installation, signed DMG and live update feed. | In progress |


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
