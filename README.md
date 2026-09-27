# SayType

Always-ready, fully local dictation for macOS. Click into any text field and just talk — no
hotkey to hold, no button to press. Pause for a moment and your words are typed in. Select text
and press **⌃⌥S** to hear it read aloud. No cloud, no subscription.

## How it works

1. **Focus**: the Accessibility API tells us when the focused element accepts text. The mic is
   only on while a text field has focus (password fields are always skipped).
2. **Voice detection**: an adaptive energy VAD tracks your room's noise floor and cuts an
   utterance when you pause (default 0.8 s).
3. **Transcription**: on-device Whisper via [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
   (Core ML / Neural Engine). Default model: Large v3 Turbo.
4. **Vocabulary**: your terms are hinted to Whisper, then known mishearings are rewritten
   (`cube cuttle` → `kubectl`, `next dot js` → `Next.js`). "Teach" records you saying a word and
   learns how the model mishears it.
5. **Typing**: inserted through Accessibility (clipboard untouched) when the app supports it,
   otherwise pasted with the clipboard restored afterwards.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌃⌥D | Turn dictation on/off |
| ⌃⌥S | Read selected text aloud (press again to stop) |

## Swapping models

**Voice → text**
- Any WhisperKit Core ML model: pick from the list or type a model name + Hugging Face repo.
- Anything else (Parakeet, whisper.cpp, MLX, …): run it as a local server with an
  OpenAI-compatible `POST /v1/audio/transcriptions` endpoint and point SayType at it.
- New engine types: implement `SpeechToTextEngine` (`SayType/STT/SpeechToText.swift`).

**Text → voice**
- macOS voices (no download), Qwen3-TTS on-device (0.6B / 1.7B), or any local server with an
  OpenAI-compatible `POST /v1/audio/speech` endpoint (e.g. Kokoro-FastAPI).
- New engine types: implement `TextToSpeechEngine` (`SayType/TTS/TextToSpeech.swift`).

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./install.sh          # build release + install to /Applications
xcodegen generate     # then open SayType.xcodeproj to develop
xcodebuild -project SayType.xcodeproj -scheme SayType -destination 'platform=macOS' test
```

On first launch grant **Microphone** and **Accessibility** access (System Settings → Privacy &
Security). The model downloads once (~630 MB) and is optimized for your Mac (a few minutes the
first time).

## Distribution

Sold directly (not the Mac App Store: the App Sandbox blocks reading other apps' text fields).
See [docs/RELEASING.md](docs/RELEASING.md). `./install.sh` installs the unsandboxed **Direct** build locally.

## Mac App Store notes (sandboxed Release config, currently not viable)

- Already sandboxed (entitlements: sandbox, microphone, outgoing network for model downloads
  and localhost servers). Signed with team `VQDNM3C2SW`.
- Licenses allow commercial use: WhisperKit (MIT), Whisper weights (MIT), Qwen3-TTS (Apache 2.0).
  Keep attribution in an About/Acknowledgements screen.
- Models are downloaded on first run (data, not code), which App Review allows. Say so in the
  description and show download size.
- Accessibility use must be explained in the review notes: it is required to detect focused
  text fields and insert text. Utilities like Magnet and PopClip ship on the store with it.
- Still to do before submission: app icon, final name, privacy policy URL (can state "no data
  collected"), onboarding window for the two permissions, App Store screenshots.
