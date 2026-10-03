# SayType

Always-ready, fully local dictation for macOS. Click into any text field and just talk, with no
key to hold. Pause for a moment and your words are typed in. Select text and press **⌃⌥S** to hear
it read aloud. No cloud, no account, no subscription. Free and open source (MIT).

Website: <https://frugoman.github.io/saytype-site/>

## Install

```bash
brew install --cask frugoman/tap/saytype
```

Update with `brew upgrade --cask saytype`. The cask also installs the `saytype` command-line tool.
Requires macOS 14 or later (Apple silicon recommended). On first launch grant **Microphone** and
**Accessibility** access (System Settings → Privacy & Security). The speech model downloads once
(about 630 MB).

## What it does

- **Listening modes.** Hands-free (default), push-to-talk (hold ⌃⌥Space, release to type) or toggle
  (press to start, press to stop). A small recording pill and optional start/stop sounds.
- **Transcript history.** Searchable list in Settings → History. Copy or type again. Stored only on
  your Mac; turn it off or clear it any time. Recent items are in the menu bar.
- **Voice commands.** "new line", "new paragraph", "scratch that", "undo that", "select all",
  "press enter", plus optional spoken punctuation ("comma", "question mark", "open paren").
- **Snippets.** Say a phrase and a saved block is typed. Placeholders: `{date}`, `{time}`,
  `{clipboard}`.
- **Per-app profiles.** Pause length, language, tone (casual, professional, code, literal),
  trailing period and extra vocabulary per app, with suggestions for Slack, Mail, Terminal, Xcode,
  VS Code, Messages and more.
- **Local AI cleanup** (off by default). Removes filler words, fixes punctuation, optional polish
  or translation, using Apple's on-device model (macOS 26+) or a local OpenAI-compatible server
  (Ollama, LM Studio, llama.cpp, mlx_lm.server).
- **Voice-edit.** Select text, press **⌃⌥E** and say "make this shorter", "translate to Spanish"
  or "fix the grammar". Needs the AI backend.
- **Languages.** About 30 languages. "Translate to English" (Whisper), "Output language" (AI
  backend), and the Parakeet v3 engine (25 European languages) alongside Whisper.
- **Files and meetings.** "Transcribe a file…" (audio or video; export .txt, .srt, .vtt, .md) and
  "Record a meeting" (system audio and microphone, labelled You and Others, optional AI summary
  with action items). Meetings need the Screen & System Audio Recording permission.
- **Read aloud.** Select text and press ⌃⌥S, using a macOS voice or an on-device voice.
- **Vocabulary.** Add your terms; "Teach" learns how the model mishears a word and fixes it
  (`cube cuttle` becomes `kubectl`).

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌃⌥D | Turn dictation on/off |
| ⌃⌥S | Read selected text aloud (press again to stop) |
| ⌃⌥Space | Push-to-talk (hold, release to type) |
| ⌃⌥E | Voice-edit the selection |

## Automation

```bash
saytype toggle
saytype speak "Build finished"
saytype transcribe ~/Recordings/interview.m4a
saytype last | pbcopy
```

`saytype help` lists every command. The same actions are available as `saytype://` URLs
(for example `open -g "saytype://dictation/toggle"`), as Shortcuts actions and as Raycast script
commands. See [integrations/](integrations/README.md).

## How it works

1. **Focus.** The Accessibility API tells us when the focused element accepts text. The mic is
   only on while a text field has focus (password fields are always skipped).
2. **Voice detection.** An adaptive energy VAD tracks your room's noise floor and cuts an
   utterance when you pause (default 0.8 s).
3. **Transcription.** On-device Whisper via [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
   (Core ML / Neural Engine), default model Large v3 Turbo, or the Parakeet v3 engine.
4. **Vocabulary.** Your terms are hinted to the model, then known mishearings are rewritten.
5. **Typing.** Inserted through Accessibility (clipboard untouched) when the app supports it,
   otherwise pasted with the clipboard restored afterwards.

## Swapping models

**Voice to text**
- Any WhisperKit Core ML model: pick from the list or type a model name and Hugging Face repo.
- Anything else (whisper.cpp, MLX, …): run it as a local server with an OpenAI-compatible
  `POST /v1/audio/transcriptions` endpoint and point SayType at it.
- New engine types: implement `SpeechToTextEngine` (`SayType/STT/SpeechToText.swift`).

**Text to voice**
- macOS voices (no download), Qwen3-TTS on-device (0.6B / 1.7B), or any local server with an
  OpenAI-compatible `POST /v1/audio/speech` endpoint (for example Kokoro-FastAPI).
- New engine types: implement `TextToSpeechEngine` (`SayType/TTS/TextToSpeech.swift`).

## Privacy

Speech is transcribed on your Mac. Audio is kept in memory only long enough to transcribe it and
is never saved or uploaded. History, snippets, profiles and vocabulary are stored locally in
`~/Library/Application Support/SayType`. There are no accounts, analytics or tracking. The only
network use is downloading models (from Hugging Face) and Homebrew installs. AI cleanup talks only
to Apple's on-device model or to the local server address you enter. Because the code is open you
can check all of this. Full policy: <https://frugoman.github.io/saytype-site/privacy/>.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./install.sh          # build release + install to /Applications
xcodegen generate     # then open SayType.xcodeproj to develop
xcodebuild -project SayType.xcodeproj -scheme SayType -destination 'platform=macOS' test
```

## Open source (MIT)

SayType is released under the [MIT License](LICENSE). Issues and pull requests are welcome. For
anything bigger than a small fix, open an issue first so we can agree on the approach. Please
keep the project's promises: everything runs locally, and no accounts, analytics or tracking.
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Distribution

Distributed through Homebrew, not the Mac App Store: the App Sandbox blocks reading other apps'
text fields. See [docs/RELEASING.md](docs/RELEASING.md). `./install.sh` installs the unsandboxed
**Direct** build locally.

## Support the project

SayType is free. If it saves you some typing, you can
[buy me a coffee](https://buymeacoffee.com/frugoman).
