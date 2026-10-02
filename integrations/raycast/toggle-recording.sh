#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start or Stop Recording
# @raycast.mode silent
# @raycast.packageName SayType

# Optional parameters:
# @raycast.icon ⏺️
# @raycast.description Start or stop a manual SayType recording.

open -g "saytype://record/toggle"
