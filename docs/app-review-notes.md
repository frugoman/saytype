# App Review notes: SayType

Paste the block below into **App Review Information → Notes** (App Store) and
**TestFlight → Test Information → Beta App Review Information** (external testing).

---

SayType is hands-free dictation for the Mac. When the user clicks into a text field in any app and speaks, SayType transcribes the speech on-device and inserts the text at the cursor. No account, no server, no data collection.

WHY SAYTYPE NEEDS ACCESSIBILITY ACCESS
Accessibility is the core of the app. Without it the app cannot work. It's used for exactly two things:
1. Reading the role of the currently focused UI element (kAXFocusedUIElementAttribute + kAXRoleAttribute) to know whether a text field is focused. The microphone is turned on ONLY while a text field is focused, and is always off in secure/password fields (AXSecureTextField).
2. Inserting the dictated text into that field, via kAXSelectedTextAttribute, or by a Command-V paste when an app doesn't support that. When SayType pastes, the user's clipboard is restored afterwards.
It is also used to read the current text selection when the user presses Control-Option-S to have it read aloud.
SayType does not read the screen, log keystrokes, or store or transmit any content from other apps.

The app asks for this permission from a first-run setup window that explains why before opening System Settings. Users who decline can still open the app, but dictation stays off until the permission is granted.

MICROPHONE
Audio is processed in memory on the device with an on-device Whisper model (Core ML) and then discarded. It is never saved or transmitted.

NETWORK
On first launch the app downloads its speech model (about 630 MB) from Hugging Face. These are model weights (data), not executable code. Optionally, advanced users can point SayType at their own OpenAI-compatible speech server, normally on localhost. It's off by default.

HOW TO TEST
1. Launch SayType. The setup window appears. Click "Allow Microphone", then "Open Accessibility Settings" and turn on SayType.
2. Wait for "Setting up the speech model" to finish. The first run takes a few minutes: download plus Core ML compilation.
3. On the "Try it" step, click in the text box and say "Hello, this is a test." Pause for a second, and the text appears.
4. Open TextEdit or Notes, click in a document, and speak. The text is typed there. The menu bar icon shows a filled microphone while listening.
5. Select some text and press Control-Option-S to hear it read aloud. Control-Option-D turns dictation on and off.

No login or demo account is needed.

Privacy policy: https://frugoman.github.io/saytype-site/privacy/
