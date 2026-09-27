#!/bin/zsh
# Build a release copy of SayType and install it in /Applications.
set -e
cd "$(dirname "$0")"
xcodegen generate -q
xcodebuild -project SayType.xcodeproj -scheme SayType -configuration Release \
  -derivedDataPath build -destination "platform=macOS,arch=arm64" build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
pkill -x SayType || true
rm -rf /Applications/SayType.app
cp -R build/Build/Products/Release/SayType.app /Applications/
open /Applications/SayType.app
echo "Installed /Applications/SayType.app"
