# MenuCue

macOS command palette for any app’s menu bar. Press **⌥⌘P** to search and run menu commands (including Services / Quick Actions).

## Requirements

- macOS 13+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Full deploy

One command ships version bump, notarized DMG, GitHub Release, Sparkle appcast, MenuCue push (Pages), and PersonalSite `downloadUrl` update:

```bash
npm run deploy -- 1.0.3          # build number = current + 1
npm run deploy -- 1.0.3 5        # explicit build number
NOTES="Bug fixes" npm run deploy -- 1.0.3
```

Then redeploy PersonalSite to Cloud Run so the marketing Download button updates. Details: [`DISTRIBUTION.md`](DISTRIBUTION.md).

## Build signed DMG only

```bash
./scripts/build-release-dmg.sh
# or: npm run release
```

Sparkle updates, keys, GitHub Releases, and PersonalSite Download sync: see [`DISTRIBUTION.md`](DISTRIBUTION.md).

## Build

```bash
cd /path/to/MenuCue
xcodegen generate
xcodebuild -scheme MenuCue -configuration Debug -derivedDataPath build/DerivedData build
```

Or open the project in Xcode:

```bash
xcodegen generate
open MenuCue.xcodeproj
```

### Install for daily use

Ad-hoc Debug builds work, but Accessibility trust is more stable when the app is signed and lives under `/Applications`:

```bash
APP=build/DerivedData/Build/Products/Debug/MenuCue.app

# Optional but recommended: Apple Development identity (from `security find-identity -v -p codesigning`)
codesign --force --deep --sign "Apple Development: Your Name (TEAMID)" \
  --entitlements Sources/MenuCue.entitlements "$APP"

rm -rf /Applications/MenuCue.app
cp -R "$APP" /Applications/MenuCue.app
codesign --force --deep --sign "Apple Development: Your Name (TEAMID)" \
  --entitlements Sources/MenuCue.entitlements /Applications/MenuCue.app

open /Applications/MenuCue.app
```

Logs (debug): `/tmp/menucue.log`

## Permissions (System Settings)

MenuCue needs these to work. Grant them the first time you launch, then quit and reopen if menus stay empty.

### 1. Accessibility — required

**System Settings → Privacy & Security → Accessibility → MenuCue → On**

Without this, MenuCue cannot read or run other apps’ menus. The in-app onboarding and Preferences both link here.

### 2. Allow in the Menu Bar — macOS Tahoe (26+)

**System Settings → Menu Bar → Allow in the Menu Bar → MenuCue → On**

(Or use **MenuCue → Menu Bar Settings…** from the menu bar extra.)

Without this, the app can run but the menu bar icon stays hidden.

### Not required

- **Input Monitoring** — not used
- **App Sandbox** — stays off (see entitlements) so Accessibility can reach other apps

## Run

1. Launch MenuCue (from Xcode, `open` on the built `.app`, or `/Applications/MenuCue.app`).
2. Confirm Accessibility (and Menu Bar allow-list on Tahoe).
3. Focus another app, then press **⌥⌘P**.
4. Type to filter, **↑/↓** to move, **Return** to run the highlighted command.

Default hotkey is **⌥⌘P**. If something else already owns **⇧⌘P**, MenuCue stays on ⌥⌘P. Change it under **Preferences… → General**.

## Features

- Global hotkey, floating palette, Accessibility menu scrape + cache, fuzzy search
- Services / Automator Quick Actions (Preferences → Include Services menu)
- Quick Action Repo Manager (menu bar): searchable catalog, install to `~/Library/Services`, community index URLs
- Status item (MenuBarExtra), embedded Preferences, Accessibility onboarding
- Per-app disable, exclude rules, command history, Tab submenu drill-down
- Themes, launch at login, i18n aliases, AppleScript extensions, Sparkle auto-updates

## Quick Action Repo Manager

Install Automator Quick Actions from a catalog, with docs and optional Homebrew dependencies.

1. MenuCue menu bar icon → **Quick Action Repo Manager…**
2. Search the combined catalog (official + any URLs you add).
3. Open a package to read its README, review brew dependencies, then **Install**.
4. Run installed actions from Finder Quick Actions or from the MenuCue palette (Preferences → Include Services menu).

**Add a community catalog:** **Add Repository…** and paste an HTTPS `index.json` URL.

**Author packages:** see [`QuickActionsCatalog/README.md`](QuickActionsCatalog/README.md). Source lives under `QuickActionsCatalog/`; zips are generated for GitHub Pages and into the app bundle for offline use.

Default remote index (GitHub Pages):

`https://walkerfirmin.github.io/MenuCue/index.json`

## Shortcuts

| Key    | Action                                               |
| ------ | ---------------------------------------------------- |
| ⌥⌘P    | Toggle palette (configurable)                        |
| ↑ / ↓  | Move selection                                       |
| Return | Run highlighted command (first result if none moved) |
| Tab    | Drill into submenu                                   |
| Delete | Leave submenu scope (when search is empty)           |
| Esc    | Clear query, leave scope, or dismiss                 |
