#!/usr/bin/env bash
# Assemble the GitHub Pages site: Quick Actions catalog + Sparkle appcast.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$ROOT/build/pages-site}"

"$ROOT/scripts/build-quick-actions-catalog.sh" "$ROOT/QuickActionsCatalog" "$DEST"

if [[ -f "$ROOT/sparkle/appcast.xml" ]]; then
  cp "$ROOT/sparkle/appcast.xml" "$DEST/appcast.xml"
  echo "==> Included sparkle/appcast.xml → $DEST/appcast.xml"
else
  echo "warning: sparkle/appcast.xml missing — Pages will not serve an update feed yet" >&2
fi

echo "==> Pages site ready: $DEST"
