#!/bin/bash
# Builds SayType (Direct config, unsandboxed), publishes the zip as a release on the public
# frugoman/homebrew-tap (this repo stays private), and updates the Homebrew cask there.
#
# The app is signed with a Developer ID Application certificate and notarized by Apple, so Gatekeeper opens it
# without any workaround.
#
# Usage: scripts/brew-release.sh   (releases the MARKETING_VERSION in project.yml)
set -euo pipefail

cd "$(dirname "$0")/.."

TAP=frugoman/homebrew-tap
APP_REPO=frugoman/saytype
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Nicolas Frugoni (VQDNM3C2SW)}"
BUILD="build/brew"
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"(.*)".*/\1/')"
TAG="saytype-v$VERSION"
ZIP="$BUILD/SayType-$VERSION.zip"

if gh release view "$TAG" --repo "$TAP" >/dev/null 2>&1; then
  echo "v$VERSION is already released. Bump MARKETING_VERSION in project.yml first." >&2
  exit 1
fi

# Signing and notarization: a Developer ID Application certificate in the login keychain, and an App Store
# Connect API key (Developer role or higher) for the notary service.
KEY_ID="${ASC_KEY_ID:-4VK7XSDKY9}"
ISSUER_ID="${ASC_ISSUER_ID:-d4f4d460-5a2d-4cfc-9bdc-14ba239ad277}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
AUTH=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

rm -rf "$BUILD"
mkdir -p "$BUILD"
xcodegen generate --quiet

echo "==> Archiving $VERSION"
xcodebuild archive \
  -project SayType.xcodeproj \
  -scheme SayType \
  -configuration Direct \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD/SayType.xcarchive" \
  -derivedDataPath "$BUILD/DerivedData" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" \
  -quiet

echo "==> Signing with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$BUILD/SayType.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist \
  -exportPath "$BUILD/export" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  -quiet
APP="$BUILD/export/SayType.app"
codesign --verify --deep --strict "$APP"

# The menu-bar popover jumps whenever its height depends on state. This lays the menu out in every state
# and stops the release if any height differs.
echo "==> Checking the menu never changes height"
"$APP/Contents/MacOS/SayType" --check-menu 2>/dev/null

echo "==> Notarizing (usually a few minutes)"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
RESULT=$(xcrun notarytool submit "$BUILD/notarize.zip" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" \
  --wait --timeout 30m 2>&1)
echo "$RESULT" | tail -4
if ! echo "$RESULT" | grep -q "status: Accepted"; then
  echo "Notarization failed. Fetch the log with: xcrun notarytool log <id> --key ... --key-id ... --issuer ..." >&2
  exit 1
fi
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo "==> Building the disk image"
DMG="$BUILD/SayType.dmg"
rm -rf "$BUILD/dmg"
mkdir -p "$BUILD/dmg"
cp -R "$APP" "$BUILD/dmg/"
ln -s /Applications "$BUILD/dmg/Applications"
hdiutil create -volname "SayType" -srcfolder "$BUILD/dmg" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
DMG_RESULT=$(xcrun notarytool submit "$DMG" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" --wait --timeout 30m 2>&1)
echo "$DMG_RESULT" | tail -3
echo "$DMG_RESULT" | grep -q "status: Accepted" || { echo "DMG notarization failed." >&2; exit 1; }
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Publishing release $TAG on $TAP"
gh release create "$TAG" "$ZIP" --repo "$TAP" --title "SayType $VERSION" \
  --notes "Install with: brew install --cask frugoman/tap/saytype"

echo "==> Publishing the download on $APP_REPO"
NOTES="$BUILD/notes.md"
awk -v v="$VERSION" '$0 == "## " v {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES"
{
  echo
  echo "**Install:** \`brew install --cask frugoman/tap/saytype\`, or download \`SayType.dmg\` below, open it and drag SayType to Applications."
  echo "Signed with a Developer ID certificate and notarized by Apple. macOS 14 or later."
} >> "$NOTES"
gh release create "v$VERSION" "$DMG" "$ZIP" --repo "$APP_REPO" --title "SayType $VERSION" --notes-file "$NOTES"

echo "==> Updating the cask in $TAP"
TMP=$(mktemp -d)
gh repo clone "$TAP" "$TMP" -- --quiet
mkdir -p "$TMP/Casks"
cat > "$TMP/Casks/saytype.rb" <<CASK
cask "saytype" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$TAP/releases/download/saytype-v#{version}/SayType-#{version}.zip"
  name "SayType"
  desc "Hands-free, fully local dictation: click into a text field and talk"
  homepage "https://frugoman.github.io/saytype-site/"

  depends_on macos: :sonoma

  app "SayType.app"
  binary "#{appdir}/SayType.app/Contents/Resources/CLI/saytype"

  uninstall quit: "com.nicolasfrugoni.saytype"

  zap trash: [
    "~/Library/Preferences/com.nicolasfrugoni.saytype.plist",
    "~/Library/Application Support/SayType",
  ]

  caveats <<~EOS
    Open SayType from /Applications and grant Microphone and Accessibility access.
    The speech model (~630 MB) downloads once on first launch.

    The saytype command is installed too. Run: saytype help
    Recording a meeting also needs Screen & System Audio Recording access
    (System Settings > Privacy & Security). Dictation does not.
  EOS
end
CASK
git -C "$TMP" add Casks/saytype.rb
git -C "$TMP" commit -m "saytype $VERSION" --quiet
git -C "$TMP" push --quiet
rm -rf "$TMP"

echo "==> Released $VERSION."
echo "    Homebrew: brew install --cask frugoman/tap/saytype"
echo "    Download: https://github.com/$APP_REPO/releases/latest/download/SayType.dmg"
