#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Copy Last Transcript
# @raycast.mode silent
# @raycast.packageName SayType

# Optional parameters:
# @raycast.icon 📋
# @raycast.description Copy the last SayType transcript to the clipboard.

open -g "saytype://history/copy-last"
