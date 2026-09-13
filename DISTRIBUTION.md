# MenuCue distribution

Developer ID signing, notarization, Sparkle updates, and marketing-site sync.

## One-time setup

### Certificates & notary

1. Import Developer ID Application (and Installer if needed) into the login Keychain. Cert materials live under `~/Documents/Certs/`.
2. Create a notarytool keychain profile (App Store Connect API key `.p8` or app-specific password):

```bash
xcrun notarytool store-credentials MenuCue-notary \
  --key ~/Documents/Certs/AuthKey_XXXXX.p8 \
  --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_UUID
```

Override with `NOTARY_PROFILE` or skip with `SKIP_NOTARIZE=1`.

### Sparkle EdDSA keys

Keys use Keychain account **`menucue`** (not the global Sparkle default).

```bash
# After a MenuCue build so Sparkle SPM artifacts exist:
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate once (prints SUPublicEDKey):
"$SPARKLE_BIN/generate_keys" --account menucue

# Export private key outside the repo:
"$SPARKLE_BIN/generate_keys" --account menucue \
  -x ~/Documents/Certs/menucue-sparkle-ed25519.txt
chmod 600 ~/Documents/Certs/menucue-sparkle-ed25519.txt
```

Public key is already set in [`project.yml`](project.yml) as `INFOPLIST_KEY_SUPublicEDKey`.

- **Feed URL:** `https://walkerfirmin.github.io/MenuCue/appcast.xml`
- **Private key:** never commit; keep in `~/Documents/Certs/` or a CI secret.

## Full deploy (recommended)

```bash
npm run deploy -- 1.0.3          # auto-increments CURRENT_PROJECT_VERSION
npm run deploy -- 1.0.3 5        # explicit build number
NOTES="…" npm run deploy -- 1.0.3
```

Runs: version bump → `build-release-dmg.sh` → `gh release create` → `publish-sparkle-appcast.sh` → commit/push MenuCue → update/push PersonalSite `platforms.json`.

Env overrides: `PERSONAL_SITE_DIR`, `SKIP_PERSONAL_SITE=1`, `SKIP_PUSH=1`, `SKIP_NOTARIZE=1`, `DRY_RUN=1`.

After PersonalSite push, **redeploy Cloud Run** so https://walkerfirmin.com/apps/MenuCue reflects the new Download URL.

## Version bump

Before each ship, edit [`project.yml`](project.yml) (or let `deploy-release.sh` do it):

- `MARKETING_VERSION` — user-facing (e.g. `1.0.2`)
- `CURRENT_PROJECT_VERSION` — integer build number (must increase)

Then `xcodegen generate` (the release script does this).

## Build signed DMG only

```bash
./scripts/build-release-dmg.sh
# or: npm run release
# SKIP_NOTARIZE=1 to skip notarytool
```

Output: `dist/MenuCue-<MARKETING_VERSION>.dmg`

## Sparkle appcast

```bash
./scripts/publish-sparkle-appcast.sh dist/MenuCue-1.0.2.dmg
# → writes sparkle/appcast.xml
```

Uses Keychain account `menucue` or `SPARKLE_ED_KEY_FILE`. Enclosure URLs:

`https://github.com/walkerfirmin/MenuCue/releases/download/<version>/MenuCue-<version>.dmg`

Commit and push `sparkle/appcast.xml` to `main`. [`.github/workflows/deploy-catalog-pages.yml`](.github/workflows/deploy-catalog-pages.yml) builds the Pages site (Quick Actions catalog + appcast) via [`scripts/build-pages-site.sh`](scripts/build-pages-site.sh).

## Publish GitHub Release

Prefer CLI when authenticated:

```bash
gh release create 1.0.2 \
  --title "MenuCue 1.0.2" \
  --notes "…" \
  dist/MenuCue-1.0.2.dmg
```

### BrowserOS (when the browser UI is required)

Use BrowserOS MCP for GitHub’s release file picker or post-deploy checks:

1. `tabs` → `navigate` to `https://github.com/walkerfirmin/MenuCue/releases/new`
2. `snapshot` → `act` to fill tag / title / notes
3. `upload` on the asset file input with local path `dist/MenuCue-<version>.dmg`
4. Publish; `snapshot`/`read` to confirm the asset download URL
5. After PersonalSite deploy: `navigate` to `https://walkerfirmin.com/apps/MenuCue` and confirm Download `href`

Pause on auth / 2FA; do not invent credentials.

Upload the DMG **before** users hit a feed entry that points at that Release URL.

## PersonalSite marketing Download

Update [`PersonalSite/public/apps/platforms.json`](../PersonalSite/public/apps/platforms.json) `downloadUrl` for MenuCue:

```text
https://github.com/walkerfirmin/MenuCue/releases/download/X.Y.Z/MenuCue-X.Y.Z.dmg
```

Redeploy Cloud Run. Do **not** host mutable `appcast.xml` under PersonalSite static assets (1-year cache).

## Verify updates

1. Install the Sparkle-keyed build from the new DMG.
2. Preferences → Updates → **Check for Updates Now…** (or wait for automatic checks).
3. Confirm feed: `curl -sL https://walkerfirmin.github.io/MenuCue/appcast.xml | head`
