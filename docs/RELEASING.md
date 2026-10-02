# Releasing SayType

SayType is free and ships through Homebrew from the public tap `frugoman/homebrew-tap`.

| Piece | Where |
| --- | --- |
| Website, privacy, support | GitHub Pages: `frugoman/saytype-site` → https://frugoman.github.io/saytype-site/ |
| Downloads (zip) | GitHub Releases on `frugoman/homebrew-tap`, tagged `saytype-v<version>` |
| Install and updates | `brew install --cask frugoman/tap/saytype`, `brew upgrade --cask saytype` |
| Tips | https://buymeacoffee.com/frugoman (`Links.coffee` in the app) |

## Shipping a release

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Run:

```bash
scripts/brew-release.sh
```

It builds the unsandboxed **Direct** configuration, zips `SayType.app`, publishes the zip as a release on
`frugoman/homebrew-tap`, and rewrites `Casks/saytype.rb` there with the new version and checksum.

The build is signed with the Apple Development identity but not notarized, so the cask removes the
quarantine flag after install. To notarize later you need a Developer ID Application certificate.
