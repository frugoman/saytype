# Releasing SayType

SayType is free and ships through Homebrew from the public tap `frugoman/homebrew-tap`.

| Piece | Where |
| --- | --- |
| Website, privacy, support | GitHub Pages: `frugoman/saytype-site` → https://frugoman.github.io/saytype-site/ |
| Downloads (zip) | GitHub Releases on `frugoman/homebrew-tap`, tagged `saytype-v<version>` |
| Direct download (DMG, zip) | GitHub Releases on `frugoman/saytype`, tagged `v<version>`; the DMG is always named `SayType.dmg`, so `releases/latest/download/SayType.dmg` is a stable link |
| Install and updates | `brew install --cask frugoman/tap/saytype`, `brew upgrade --cask saytype` |
| Tips | https://buymeacoffee.com/frugoman (`Links.coffee` in the app) |

## Shipping a release

1. Bump `MARKETING_VERSION` in `project.yml` and add the version's entry to `CHANGELOG.md`.
   The `saytype` command-line tool reports its own version (`VERSION` in
   `SayType/Resources/CLI/saytype`), so keep that in step.
2. Run:

```bash
scripts/brew-release.sh
```

It builds the unsandboxed **Direct** configuration, zips `SayType.app`, publishes the zip as a release on
`frugoman/homebrew-tap`, and rewrites `Casks/saytype.rb` there with the new version and checksum.

The cask also installs the `saytype` command-line tool (`binary` stanza pointing at
`SayType.app/Contents/Resources/CLI/saytype`), so the app bundle must contain that script, executable.

The source is open (MIT). Tagging a release on the app repository (`git tag v<version>`) is optional
and does not change the flow above: the Homebrew release on the tap is what users install.

## Signing and notarization

The script archives the Direct configuration, exports it signed with the **Developer ID Application**
certificate, submits it to Apple's notary service, staples the ticket, and checks Gatekeeper accepts it. The
release is aborted if notarization isn't accepted. Users need no quarantine workaround.

One-time setup (already done for this Mac):
- A Developer ID Application certificate in the login keychain. Only the Account Holder can create it, at
  developer.apple.com → Certificates → Developer ID Application (G2). It is valid until 2031.
- An App Store Connect API key (`~/.appstoreconnect/private_keys/AuthKey_<id>.p8`). The script defaults to
  key `4VK7XSDKY9`; override with `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH`.

To release from another Mac, export the certificate with its private key from Keychain Access and import it there.
