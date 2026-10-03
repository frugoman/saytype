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

echo "==> Publishing release $TAG on $TAP"
gh release create "$TAG" "$ZIP" --repo "$TAP" --title "SayType $VERSION" \
  --notes "Install with: brew install --cask frugoman/tap/saytype"

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

echo "==> Released $VERSION. Install with: brew install --cask frugoman/tap/saytype"
