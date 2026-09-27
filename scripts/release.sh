#!/bin/zsh
# Build, notarize and publish a SayType release with Sparkle auto-update.
# Usage: scripts/release.sh 0.2.0 ["What's new in this version"]
#
# Produces a notarized DMG, uploads it to GitHub Releases on frugoman/saytype-site,
# and adds it to the Sparkle appcast so existing users get the update automatically.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Usage: scripts/release.sh <version> [notes]}
NOTES=${2:-"Improvements and fixes."}
BUILD=$(date +%Y%m%d%H%M)
KEY_ID=${ASC_KEY_ID:-4VK7XSDKY9}
ISSUER=${ASC_ISSUER_ID:-d4f4d460-5a2d-4cfc-9bdc-14ba239ad277}
KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
SITE=${SITE_REPO:-$HOME/dev/saytype-site}
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
AUTH=(-allowProvisioningUpdates -authenticationKeyPath $KEY_PATH -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER)
OUT=build/release
rm -rf $OUT build/SayType-Direct.xcarchive && mkdir -p $OUT

echo "▸ Archiving SayType $VERSION ($BUILD)"
xcodegen generate -q
xcodebuild -project SayType.xcodeproj -scheme SayType -configuration Direct \
  -destination 'generic/platform=macOS' -archivePath build/SayType-Direct.xcarchive \
  -derivedDataPath build MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD $AUTH archive \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

echo "▸ Signing with Developer ID"
xcodebuild -exportArchive -archivePath build/SayType-Direct.xcarchive -exportPath $OUT \
  -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist $AUTH \
  | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"
codesign --verify --deep --strict $OUT/SayType.app

echo "▸ Building DMG"
STAGE=$OUT/dmg && mkdir -p $STAGE
cp -R $OUT/SayType.app $STAGE/ && ln -s /Applications $STAGE/Applications
hdiutil create -quiet -volname "SayType" -srcfolder $STAGE -ov -format UDZO $OUT/SayType.dmg

echo "▸ Notarizing (usually 1–5 minutes)"
xcrun notarytool submit $OUT/SayType.dmg --key $KEY_PATH --key-id $KEY_ID --issuer $ISSUER --wait
xcrun stapler staple $OUT/SayType.dmg
spctl -a -t open --context context:primary-signature -v $OUT/SayType.dmg

echo "▸ Signing update for Sparkle"
SIG=$($SPARKLE_BIN/sign_update --account saytype $OUT/SayType.dmg)   # sparkle:edSignature="…" length="…"

echo "▸ Publishing GitHub release"
TAG=v$VERSION
gh release create $TAG $OUT/SayType.dmg --repo frugoman/saytype-site --title "SayType $VERSION" --notes "$NOTES"

echo "▸ Updating appcast"
python3 scripts/update_appcast.py "$SITE/appcast.xml" "$VERSION" "$BUILD" "$SIG" \
  "https://github.com/frugoman/saytype-site/releases/download/$TAG/SayType.dmg" "$NOTES"
git -C "$SITE" add appcast.xml
git -C "$SITE" commit -qm "Release SayType $VERSION"
git -C "$SITE" push -q
echo "✓ SayType $VERSION released. Download: https://github.com/frugoman/saytype-site/releases/latest/download/SayType.dmg"
