#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Dictation
# @raycast.mode silent
# @raycast.packageName SayType

# Optional parameters:
# @raycast.icon 🎙️
# @raycast.description Turn SayType dictation on or off.

open -g "saytype://dictation/toggle"
