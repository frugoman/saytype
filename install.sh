#!/bin/zsh
# Build a release copy of VoiceTyper and install it in /Applications.
set -e
cd "$(dirname "$0")"
xcodegen generate -q
xcodebuild -project VoiceTyper.xcodeproj -scheme VoiceTyper -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
pkill -x VoiceTyper || true
rm -rf /Applications/VoiceTyper.app
cp -R build/Build/Products/Release/VoiceTyper.app /Applications/
open /Applications/VoiceTyper.app
echo "Installed /Applications/VoiceTyper.app"
