#!/usr/bin/env bash
# Full MenuCue release deploy: version bump → signed DMG → GitHub Release →
# Sparkle appcast → push MenuCue (Pages) → update PersonalSite download URL.
#
# Usage:
#   ./scripts/deploy-release.sh <marketing-version> [build-number]
#   npm run deploy -- 1.0.3
#   npm run deploy -- 1.0.3 5
#
# Env:
#   NOTES                 Release notes body (default: short Sparkle/DMG blurb)
#   PERSONAL_SITE_DIR     Path to PersonalSite repo (default: ../PersonalSite)
#   GITHUB_REPO           owner/repo (default: walkerfirmin/MenuCue)
#   SKIP_NOTARIZE=1       Passed through to build-release-dmg.sh
#   SKIP_PERSONAL_SITE=1  Skip platforms.json update / PersonalSite push
#   SKIP_PUSH=1           Build + Release + appcast locally; do not git push
#   DRY_RUN=1             Print steps only; no builds or git writes
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GITHUB_REPO="${GITHUB_REPO:-walkerfirmin/MenuCue}"
PERSONAL_SITE_DIR="${PERSONAL_SITE_DIR:-$ROOT/../PersonalSite}"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: deploy-release.sh <marketing-version> [build-number]

  marketing-version   e.g. 1.0.3 (required)
  build-number        CFBundleVersion integer (default: current + 1)

Examples:
  ./scripts/deploy-release.sh 1.0.3
  npm run deploy -- 1.0.3 5
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -ge 1 ]] || { usage >&2; exit 1; }

VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)?$ ]] \
  || die "invalid marketing version: $VERSION (expected like 1.0.3)"

require_cmd() {
  command -v "$1" >/dev/null || die "$1 not found"
}

require_cmd python3
require_cmd git
require_cmd xcodegen

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  require_cmd gh
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run: gh auth login"
fi

current_marketing="$(
  python3 - <<'PY' "$ROOT/project.yml"
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
current_build="$(
  python3 - <<'PY' "$ROOT/project.yml"
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
[[ -n "$current_build" ]] || die "could not read CURRENT_PROJECT_VERSION from project.yml"

if [[ $# -ge 2 ]]; then
  BUILD="$2"
  [[ "$BUILD" =~ ^[0-9]+$ ]] || die "build-number must be an integer"
else
  BUILD="$((current_build + 1))"
fi

if [[ "$BUILD" -le "$current_build" ]]; then
  die "build-number $BUILD must be greater than current $current_build"
fi

NOTES="${NOTES:-MenuCue ${VERSION}. Signed and notarized DMG with Sparkle auto-updates.}"
DMG_PATH="$ROOT/dist/MenuCue-${VERSION}.dmg"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/MenuCue-${VERSION}.dmg"

echo "==> Deploy MenuCue ${VERSION} (build ${BUILD})"
echo "    was:     ${current_marketing} / ${current_build}"
echo "    dmg:     ${DMG_PATH}"
echo "    release: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
echo "    feed:    https://walkerfirmin.github.io/MenuCue/appcast.xml"
echo "    site:    ${PERSONAL_SITE_DIR}"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "==> DRY_RUN=1 — stopping before mutations"
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  die "MenuCue working tree is dirty — commit or stash before deploy"
fi

# --- 1. Version bump ---
echo "==> Bumping project.yml"
python3 - <<PY
from pathlib import Path
import re
path = Path(r"$ROOT/project.yml")
text = path.read_text(encoding="utf-8")
text2, n1 = re.subn(
    r'(MARKETING_VERSION:\s*")[^"]+(")',
    r'\g<1>${VERSION}\2',
    text,
    count=1,
)
text2, n2 = re.subn(
    r'(CURRENT_PROJECT_VERSION:\s*")[^"]+(")',
    r'\g<1>${BUILD}\2',
    text2,
    count=1,
)
if n1 != 1 or n2 != 1:
    raise SystemExit(f"version replace failed (marketing={n1}, build={n2})")
path.write_text(text2, encoding="utf-8")
print("    MARKETING_VERSION=${VERSION}")
print("    CURRENT_PROJECT_VERSION=${BUILD}")
PY

# --- 2. Build / notarize ---
echo "==> Building signed DMG"
"$ROOT/scripts/build-release-dmg.sh"
[[ -f "$DMG_PATH" ]] || die "expected DMG missing: $DMG_PATH"

# --- 3. GitHub Release (DMG must exist before appcast consumers hit the URL) ---
echo "==> Creating GitHub Release ${VERSION}"
if gh release view "$VERSION" -R "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "    release ${VERSION} already exists — uploading asset if needed"
  if ! gh release view "$VERSION" -R "$GITHUB_REPO" --json assets -q '.assets[].name' 2>/dev/null | grep -qx "MenuCue-${VERSION}.dmg"; then
    gh release upload "$VERSION" "$DMG_PATH" -R "$GITHUB_REPO" --clobber
  else
    echo "    MenuCue-${VERSION}.dmg already on release"
  fi
else
  gh release create "$VERSION" \
    -R "$GITHUB_REPO" \
    --title "MenuCue ${VERSION}" \
    --notes "$NOTES" \
    "$DMG_PATH"
fi

# --- 4. Sparkle appcast ---
echo "==> Generating Sparkle appcast"
"$ROOT/scripts/publish-sparkle-appcast.sh" "$DMG_PATH" "$VERSION"
[[ -f "$ROOT/sparkle/appcast.xml" ]] || die "appcast.xml missing after publish"

# --- 5. Commit + push MenuCue ---
echo "==> Committing MenuCue release files"
git add project.yml sparkle/appcast.xml
# xcodegen + release build may refresh the Xcode project and bundled catalog
[[ -f MenuCue.xcodeproj/project.pbxproj ]] && git add MenuCue.xcodeproj/project.pbxproj
[[ -d Resources/QuickActionsCatalog ]] && git add Resources/QuickActionsCatalog

if git diff --cached --quiet; then
  echo "    warning: nothing staged to commit (version/appcast may already be committed)"
else
  git commit -m "$(cat <<EOF
Release MenuCue ${VERSION} (build ${BUILD}).

Ship notarized DMG, Sparkle appcast, and version bump for GitHub Releases / Pages.
EOF
)"
fi

if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  echo "==> Pushing MenuCue main (triggers Pages appcast deploy)"
  git push origin HEAD
else
  echo "==> SKIP_PUSH=1 — not pushing MenuCue"
fi

# --- 6. PersonalSite marketing Download ---
if [[ "${SKIP_PERSONAL_SITE:-0}" == "1" ]]; then
  echo "==> SKIP_PERSONAL_SITE=1 — skipping platforms.json"
else
  [[ -d "$PERSONAL_SITE_DIR/.git" ]] || die "PersonalSite repo not found at $PERSONAL_SITE_DIR (set PERSONAL_SITE_DIR)"
  PLATFORMS="$PERSONAL_SITE_DIR/public/apps/platforms.json"
  [[ -f "$PLATFORMS" ]] || die "missing $PLATFORMS"

  if [[ -n "$(git -C "$PERSONAL_SITE_DIR" status --porcelain)" ]]; then
    die "PersonalSite working tree is dirty — commit or stash before deploy"
  fi

  echo "==> Updating PersonalSite downloadUrl → ${DOWNLOAD_URL}"
  python3 - <<PY
import json
from pathlib import Path
path = Path("$PLATFORMS")
data = json.loads(path.read_text(encoding="utf-8"))
updated = 0
for platform in data.get("platforms", []):
    for child in platform.get("children", []):
        if child.get("name") == "MenuCue":
            child["downloadUrl"] = "$DOWNLOAD_URL"
            updated += 1
if updated != 1:
    raise SystemExit(f"expected 1 MenuCue entry, updated {updated}")
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("    platforms.json updated")
PY

  git -C "$PERSONAL_SITE_DIR" add public/apps/platforms.json
  if git -C "$PERSONAL_SITE_DIR" diff --cached --quiet; then
    echo "    platforms.json already pointed at this URL"
  else
    git -C "$PERSONAL_SITE_DIR" commit -m "$(cat <<EOF
Point MenuCue Download at the ${VERSION} GitHub Release DMG.

EOF
)"
  fi

  if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
    echo "==> Pushing PersonalSite main"
    git -C "$PERSONAL_SITE_DIR" push origin HEAD
  else
    echo "==> SKIP_PUSH=1 — not pushing PersonalSite"
  fi

  echo ""
  echo "==> PersonalSite: redeploy Cloud Run so walkerfirmin.com/apps/MenuCue picks up Download."
fi

echo ""
echo "==> Deploy complete: MenuCue ${VERSION} (build ${BUILD})"
echo "    DMG:      ${DMG_PATH}"
echo "    Release:  https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
echo "    Appcast:  https://walkerfirmin.github.io/MenuCue/appcast.xml"
echo "    Download: ${DOWNLOAD_URL}"
echo "    Verify:   curl -sL https://walkerfirmin.github.io/MenuCue/appcast.xml | head"
