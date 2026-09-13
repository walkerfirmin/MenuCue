#!/usr/bin/env bash
# Generate / update Sparkle appcast.xml for a MenuCue release DMG.
#
# Usage: publish-sparkle-appcast.sh <dmg-path> [version]
#
# Env:
#   SPARKLE_ACCOUNT     Keychain account for EdDSA key (default: menucue)
#   SPARKLE_ED_KEY_FILE Private key file (default: ~/Documents/Certs/menucue-sparkle-ed25519.txt)
#   GITHUB_REPO         owner/repo for enclosure URLs (default: walkerfirmin/MenuCue)
#
# Writes: sparkle/appcast.xml (committed / published via GitHub Pages)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -ge 1 ]] || die "usage: $0 <dmg-path> [version]"

DMG_PATH="$1"
[[ -f "$DMG_PATH" ]] || die "DMG not found: $DMG_PATH"
DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd)/$(basename "$DMG_PATH")"

VERSION="${2:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(basename "$DMG_PATH" | sed -n 's/^MenuCue-\(.*\)\.dmg$/\1/p')"
fi
[[ -n "$VERSION" ]] || die "could not infer version from DMG name; pass version as arg 2"

SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-menucue}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-$HOME/Documents/Certs/menucue-sparkle-ed25519.txt}"
GITHUB_REPO="${GITHUB_REPO:-walkerfirmin/MenuCue}"
DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/"

resolve_generate_appcast() {
  if [[ -n "${GENERATE_APPCAST:-}" && -x "$GENERATE_APPCAST" ]]; then
    printf '%s\n' "$GENERATE_APPCAST"
    return
  fi
  local candidates=(
    "$ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && { printf '%s\n' "$c"; return; }
  done
  # Fall back to any DerivedData copy under the repo
  local found
  found="$(find "$ROOT/build" -name generate_appcast -type f 2>/dev/null | head -1 || true)"
  [[ -n "$found" && -x "$found" ]] || die "generate_appcast not found — build MenuCue once so Sparkle SPM artifacts exist"
  printf '%s\n' "$found"
}

GEN="$(resolve_generate_appcast)"
STAGE="$ROOT/build/sparkle-archives"
SPARKLE_DIR="$ROOT/sparkle"
mkdir -p "$STAGE" "$SPARKLE_DIR"

# Reuse prior appcast so historical entries keep their enclosure URLs.
if [[ -f "$SPARKLE_DIR/appcast.xml" ]]; then
  cp "$SPARKLE_DIR/appcast.xml" "$STAGE/appcast.xml"
fi

# Stage only the new DMG (plus existing appcast). Old DMGs are not required
# when their entries already exist in appcast.xml.
rm -f "$STAGE"/MenuCue-*.dmg
cp "$DMG_PATH" "$STAGE/$(basename "$DMG_PATH")"

echo "==> Generating appcast"
echo "    dmg:      $(basename "$DMG_PATH")"
echo "    version:  $VERSION"
echo "    prefix:   $DOWNLOAD_PREFIX"

GEN_ARGS=(
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --link "https://walkerfirmin.com/apps/MenuCue"
  --account "$SPARKLE_ACCOUNT"
)
if [[ -f "$SPARKLE_ED_KEY_FILE" ]]; then
  GEN_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi

"$GEN" "${GEN_ARGS[@]}" "$STAGE"

[[ -f "$STAGE/appcast.xml" ]] || die "generate_appcast did not write appcast.xml"
cp "$STAGE/appcast.xml" "$SPARKLE_DIR/appcast.xml"

echo "==> Wrote $SPARKLE_DIR/appcast.xml"
echo "    Commit sparkle/appcast.xml and push to main (Pages workflow publishes it)."
echo "    Upload the DMG to GitHub Release tag ${VERSION} before users hit the feed."
