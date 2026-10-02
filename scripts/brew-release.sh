#!/bin/bash
# Builds SayType (Direct config, unsandboxed), publishes the zip as a release on the public
# frugoman/homebrew-tap (this repo stays private), and updates the Homebrew cask there.
#
# The app is signed with the project's Apple Development identity but not notarized, so the cask drops the
# quarantine flag after install.
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

rm -rf "$BUILD"
mkdir -p "$BUILD"
xcodegen generate --quiet

echo "==> Building $VERSION"
xcodebuild build \
  -project SayType.xcodeproj \
  -scheme SayType \
  -configuration Direct \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" \
  -quiet

cp -R "$BUILD/DerivedData/Build/Products/Direct/SayType.app" "$BUILD/SayType.app"
codesign --verify --deep --strict "$BUILD/SayType.app"
ditto -c -k --keepParent "$BUILD/SayType.app" "$ZIP"
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

  # The app is not notarized, so drop the quarantine flag to let Gatekeeper open it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/SayType.app"],
                          writable_paths: ["SayType.app"], writable_base: :appdir
  end

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
