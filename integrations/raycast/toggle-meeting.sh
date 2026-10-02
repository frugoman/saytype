#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Record or Stop Meeting
# @raycast.mode silent
# @raycast.packageName SayType

# Optional parameters:
# @raycast.icon 👥
# @raycast.description Start or stop recording a meeting.

open -g "saytype://meeting/toggle"
