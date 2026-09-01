# Vox for iPhone MVP

This Xcode project contains an iOS 18+ host app and custom keyboard extension.
The host app owns microphone capture, OpenAI access, cleanup, dictionary, and
history. The keyboard exchanges only request state and completed text through
the App Group container.

## Build and install

1. Open `VoxMobile.xcodeproj` in Xcode.
2. Select an Apple Development team for both targets.
3. Confirm these identifiers exist for that team:
   - `com.andykumeda.vox.ios`
   - `com.andykumeda.vox.ios.keyboard`
   - App Group `group.com.andykumeda.vox`
4. Run the `VoxMobile` scheme on an iPhone running iOS 18 or later.
5. Open Vox once, enter an OpenAI API key, and grant microphone access.
6. In iPhone Settings, add **Vox Keyboard** and enable **Allow Full Access**.

## Expected keyboard handoff

Tap the keyboard microphone. iOS opens Vox so the containing app can activate
the microphone. Once recording starts, swipe back to the original app, speak,
and tap Stop on the keyboard. Vox transcribes in the background and the
keyboard inserts only the result matching that request ID.

This handoff must be validated on a physical iPhone. Custom keyboards cannot
access the microphone themselves, secure fields can replace third-party
keyboards, and some apps disable third-party keyboards entirely.
