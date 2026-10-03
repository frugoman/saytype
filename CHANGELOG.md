# Changelog

## 1.1.6

- Fixed SayType turning listening on and off every few seconds with "Pause while other audio plays"
  on. It counted its own audio as other audio playing; it now only pauses for sound from other apps.

## 1.1.5

- The menu-bar popover no longer resizes or jumps while you talk. Every part of it now has a fixed
  height, and each release checks that the menu is the same height in every state.

## 1.1.4

- The floating mic badge and the menu now always show the real state. A short noise (a cough, a click)
  used to leave SayType showing "hearing" even after the microphone had turned off. When it's paused,
  the badge says why (push-to-talk mode, audio playing, a meeting being recorded).
- Voice commands are harder to trigger by accident: "scratch that" at the start of a sentence and
  "delete that" in the middle of one are typed as words, and "enter", "return" and "undo" only count
  when said on their own.
- "Scratch that" never deletes text SayType didn't type, and there's no stray space after a new line
  or after pressing Enter.
- Your clipboard is restored correctly after dictations that paste more than once, and after reading
  the selection aloud (images and files included).
- Numbers in brackets, like a phone number's area code, are no longer removed.
- Voice-edit instructions are never typed into your document.
- Pressing push-to-talk twice quickly no longer mixes two recordings.
- Read aloud: a second request while speaking no longer turns the mic back on mid-sentence.
- Meetings: starting twice quickly can't crash, and the microphone keeps recording when the audio
  device changes. Local speech servers get real timestamps and enough time for long files.
- Two actions with the same shortcut are flagged in Settings.
- Lower CPU use: the menu no longer redraws constantly.

## 1.1.3

- Fixed the menu-bar popover wobbling: its background no longer animates (it kept re-laying out the
  popover). The drifting shapes in the other windows are also lighter on the CPU.

## 1.1.2

- Fixed a crash when the microphone started while the input device was changing (switching
  headsets or inputs, or listening turning on and off as music plays).

## 1.1.1

- Fixed the menu-bar popover flickering open and closed (the mic badge window no longer animates).
- History keeps only the most recent items: 10 by default, configurable in Settings → History.
  Lowering the number deletes the older items.

## 1.1.0

- Listening modes: hands-free (the default, as before), push-to-talk (hold ⌃⌥Space and release
  to type) and toggle (press to start, press to stop). A small on-screen recording pill and
  optional start and stop sounds.
- Transcript history: a searchable list in Settings → History. Copy an item or type it again.
  Stored only on this Mac, can be turned off or cleared. The menu bar shows recent items.
- Voice commands: "new line", "new paragraph", "scratch that", "undo that", "select all",
  "press enter", plus optional spoken punctuation ("comma", "question mark", "open paren").
- Snippets: say a phrase and a saved block of text is typed. Placeholders: `{date}`, `{time}`,
  `{clipboard}`.
- Per-app profiles: pause length, language, tone (casual, professional, code, literal), removing
  the trailing period, and extra vocabulary for each app. Suggested profiles for Slack, Mail,
  Terminal, Xcode, VS Code, Messages and more.
- Local AI cleanup (off by default): removes filler words, fixes punctuation, optional polish
  and translation. Uses Apple's on-device model (macOS 26 or later) or any local
  OpenAI-compatible server (Ollama, LM Studio, llama.cpp, mlx_lm.server). Nothing leaves the Mac.
- Voice-edit: select text, press ⌃⌥E and say what to change ("make this shorter", "translate to
  Spanish", "fix the grammar"). Needs the AI backend.
- About 30 languages. "Translate to English" (Whisper) and "Output language" (AI backend). The
  Parakeet v3 engine (25 European languages, very fast) joins Whisper.
- File and meeting transcription: "Transcribe a file…" (any audio or video; export .txt, .srt,
  .vtt, .md) and "Record a meeting" (system audio and microphone, labelled You and Others,
  optional AI summary with action items). Meetings need the Screen & System Audio Recording
  permission.
- Automation: the `saytype` command-line tool (installed by the Homebrew cask), the `saytype://`
  URL scheme, Shortcuts actions and Raycast script commands. See `integrations/`.
- Rename the command: Settings → Automation lets you call the command-line tool anything you like
  (`alfred toggle` instead of `saytype toggle`).
- A mic badge that follows the text cursor and shows what SayType is really doing, with a live
  level. It turns orange if the microphone stops delivering audio.
- A new look: pastel and playful, with a colour-coded sidebar, animations, a "Saved" indicator,
  and an Appearance pane (palettes, accent colours, light and dark, corners, spacing, font).
- Fixes: the microphone restarts after an audio device change or sleep; voice commands ignore
  fillers like "uh"; language lists only show languages the chosen engine or AI model supports.
- Signed with a Developer ID certificate and notarized by Apple. Download the DMG or install with
  Homebrew.
- SayType is open source under the MIT license.
