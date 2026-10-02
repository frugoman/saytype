# SayType for Raycast

Script Commands that control SayType from [Raycast](https://raycast.com). Each one opens a
`saytype://` URL in the background, so nothing is installed besides these files.

| Script | What it does |
| --- | --- |
| `toggle-dictation.sh` | Turn dictation on or off |
| `toggle-recording.sh` | Start or stop a manual recording |
| `speak-selection.sh` | Read the selected text aloud |
| `edit-selection.sh` | Voice-edit the selected text (needs the AI backend) |
| `copy-last-transcript.sh` | Copy the last transcript to the clipboard |
| `toggle-meeting.sh` | Start or stop recording a meeting |

## Add them to Raycast

1. Get this folder on your Mac (clone the repository or download it).
2. Open Raycast, search for **Extensions**, and choose **Script Commands**.
3. Click **Add Script Directory** (or open Raycast Settings, then Extensions, then **+**, then
   **Add Script Directory**) and select this `integrations/raycast` folder.
4. The six commands appear under the package name **SayType**. Give them hotkeys or aliases in
   Raycast Settings → Extensions.

The scripts need to stay executable (`chmod +x *.sh`) if you copy them somewhere else.
SayType starts if it is not running.
