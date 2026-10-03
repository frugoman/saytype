# Changelog

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
