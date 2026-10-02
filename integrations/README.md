# Automating SayType

SayType can be driven from the terminal, from links, from Shortcuts and from Raycast. All of it
is local: the commands only talk to the SayType app on your Mac.

## Command line

The Homebrew cask installs a `saytype` command:

```bash
brew install --cask frugoman/tap/saytype
saytype help
```

| Command | What it does |
| --- | --- |
| `saytype toggle` / `on` / `off` | Turn dictation on or off |
| `saytype record [start\|stop\|toggle]` | Manual recording (default: toggle) |
| `saytype speak [text…]` | Read text aloud. With no text, reads the current selection |
| `saytype edit` | Voice-edit the current selection |
| `saytype transcribe <file>` | Transcribe an audio or video file |
| `saytype meeting start\|stop` | Start or stop recording a meeting |
| `saytype copy-last` | Copy the last transcript to the clipboard |
| `saytype last` | Print the last transcript |
| `saytype status` | Print one word: `listening`, `idle`, `off`, `loading`, `speaking` or `recording` |
| `saytype version`, `saytype help` | Version and usage |

Commands that act run `open -g "saytype://…"`, so SayType starts in the background if it is not
running. `last` and `status` read small files in `~/Library/Application Support/SayType/`
(`last-transcript.txt` and `status.txt`). If SayType is not running, `status` prints `off`.

Exit codes: `0` success, `1` failed (for example no transcript yet, or a file that does not
exist), `2` usage error.

```bash
saytype speak "The build finished"
saytype transcribe ~/Recordings/interview.m4a
saytype last | pbcopy
```

The script is `SayType/Resources/CLI/saytype`. It is plain bash 3.2 and uses only tools that ship
with macOS (`open`, `perl` for URL-encoding text).

## URL scheme

| URL | Action |
| --- | --- |
| `saytype://dictation/toggle`, `/on`, `/off` | Turn dictation on or off |
| `saytype://record/start`, `/stop`, `/toggle` | Manual recording |
| `saytype://speak?text=…` | Read the text aloud. Leave out `text` to read the selection |
| `saytype://edit` | Voice-edit the selection |
| `saytype://transcribe?file=/absolute/path` | Transcribe a file |
| `saytype://meeting/start`, `/stop`, `/toggle` | Meeting recording |
| `saytype://history/copy-last` | Copy the last transcript |
| `saytype://settings` | Open Settings |

URL-encode the values. Example: `open -g "saytype://speak?text=Hello%20there"`.

## Shortcuts

SayType adds actions to the Shortcuts app. Search for SayType in the action list:

- **Toggle Dictation**, **Start Dictation**, **Stop Dictation**
- **Speak Text**
- **Get Last Transcript**
- **Transcribe Audio File**

Combine them with anything Shortcuts can do: run one from the menu bar, a keyboard shortcut, a
Focus change or Siri.

## Raycast

See [raycast/README.md](raycast/README.md) for the script commands.
