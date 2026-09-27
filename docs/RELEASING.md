# Selling & releasing SayType

Everything runs on free services. The only fixed cost is the Apple Developer Program you already pay.

| Piece | Where |
| --- | --- |
| Website, privacy, support | GitHub Pages: `frugoman/saytype-site` → https://frugoman.github.io/saytype-site/ |
| Downloads (DMG) | GitHub Releases on `frugoman/saytype-site` (latest: `/releases/latest/download/SayType.dmg`) |
| Auto-updates | Sparkle reads `appcast.xml` on the site; updates are EdDSA-signed |
| Payments + license keys | Lemon Squeezy (Merchant of Record: handles VAT/sales tax; ~5% + 50¢ per sale) |
| Notarization | Apple notary service via the App Store Connect API key |

## One-time setup (you)

1. **Developer ID certificate** (Account Holder only):
   Xcode → Settings → Accounts → add your Apple ID → select team → **Manage Certificates…** →
   **+** → **Developer ID Application**.
2. **Lemon Squeezy**: create an account and store, then a product "SayType":
   - Pricing: single payment (e.g. $12).
   - Enable **License keys**, activation limit 2, never expire.
   - Copy the store ID, product ID and the checkout link.
3. Put those into `SayType/Licensing/LicenseConfig` (`storeID`, `productID`, `checkoutURL`) and the
   checkout link into `saytype-site/index.html` (`data-checkout`).
4. Back up `~/Documents/SayType-Secrets/sparkle-private-key.txt` in your password manager.
   **If you lose it you can never ship another update to existing users.** It's also in your login
   Keychain as "Private key for signing Sparkle updates" (account `saytype`).

## Shipping a release

```bash
scripts/release.sh 0.2.0 "Faster transcription and a new voice."
```

It archives the Direct build, signs it with Developer ID, builds a DMG, notarizes and staples it,
signs the update for Sparkle, creates the GitHub release, and updates the appcast. Existing users
get the update within a day, or right away with "Check for Updates…".

## Trial & licensing behaviour

- 14-day trial starting on first launch (stored in the Keychain, survives reinstalls).
- Keys are activated per Mac through the public Lemon Squeezy License API; re-validated weekly.
  Offline use never locks anyone out, and only an explicit "invalid" answer (refund, disabled key)
  removes the license.
- "Deactivate This Mac" in Settings → License frees an activation slot.
