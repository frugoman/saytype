#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Speak Selection
# @raycast.mode silent
# @raycast.packageName SayType

# Optional parameters:
# @raycast.icon 🔊
# @raycast.description Read the selected text aloud.

open -g "saytype://speak"
