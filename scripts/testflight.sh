#!/bin/zsh
# Archive SayType and upload it to App Store Connect / TestFlight.
# Usage: scripts/testflight.sh [build-number]   (defaults to a timestamp)
set -e
cd "$(dirname "$0")/.."
KEY_ID=${ASC_KEY_ID:-4VK7XSDKY9}
ISSUER=${ASC_ISSUER_ID:-d4f4d460-5a2d-4cfc-9bdc-14ba239ad277}
KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
BUILD=${1:-$(date +%Y%m%d%H%M)}
AUTH=(-allowProvisioningUpdates -authenticationKeyPath $KEY_PATH -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER)

xcodegen generate -q
rm -rf build/SayType.xcarchive build/export
xcodebuild -project SayType.xcodeproj -scheme SayType -configuration Release \
  -destination 'generic/platform=macOS' -archivePath build/SayType.xcarchive \
  CURRENT_PROJECT_VERSION=$BUILD $AUTH archive | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"
xcodebuild -exportArchive -archivePath build/SayType.xcarchive -exportPath build/export \
  -exportOptionsPlist scripts/ExportOptions.plist $AUTH | grep -E "error:|Upload|EXPORT (SUCCEEDED|FAILED)|progress"
echo "Uploaded build $BUILD. It appears in App Store Connect → TestFlight after processing (~10-30 min)."
