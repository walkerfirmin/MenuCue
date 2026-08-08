#!/usr/bin/env bash
# Build MenuCue (Debug), install to /Applications/MenuCue.app, and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_SRC="$ROOT/build/DerivedData/Build/Products/Debug/MenuCue.app"
APP_DST="/Applications/MenuCue.app"
ENTITLEMENTS="$ROOT/Sources/MenuCue.entitlements"
SCHEME="MenuCue"
CONFIGURATION="Debug"

die() {
  echo "error: $*" >&2
  exit 1
}

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"

# Prefer an Apple Development identity; fall back to ad-hoc signing.
resolve_identity() {
  local identity
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' \
      | head -1
  )"
  if [[ -n "${identity}" ]]; then
    printf '%s\n' "${identity}"
  else
    printf '%s\n' "-"
  fi
}

echo "==> Stopping MenuCue (if running)"
pkill -x MenuCue 2>/dev/null || true

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "$ROOT/build/DerivedData" \
  -destination 'platform=macOS,arch=arm64' \
  build

[[ -d "${APP_SRC}" ]] || die "build product missing: ${APP_SRC}"

IDENTITY="$(resolve_identity)"
echo "==> Signing with: ${IDENTITY}"

codesign --force --deep --sign "${IDENTITY}" \
  --entitlements "${ENTITLEMENTS}" \
  "${APP_SRC}"

echo "==> Installing to ${APP_DST}"
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"

codesign --force --deep --sign "${IDENTITY}" \
  --entitlements "${ENTITLEMENTS}" \
  "${APP_DST}"

echo "==> Launching ${APP_DST}"
open "${APP_DST}"

sleep 1
if pgrep -qx MenuCue; then
  echo "==> MenuCue is running (pid $(pgrep -x MenuCue | tr '\n' ' '))"
else
  die "MenuCue did not stay running"
fi
