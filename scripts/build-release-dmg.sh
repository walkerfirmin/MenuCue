#!/usr/bin/env bash
# Build a Developer ID–signed MenuCue Release DMG (optionally notarize + staple).
#
# Env:
#   CODE_SIGN_IDENTITY  Override signing identity (default: first Developer ID Application)
#   TEAM_ID             Default H297ZX38YB (informational / xcodebuild)
#   NOTARY_PROFILE      notarytool keychain profile (default: MenuCue-notary)
#   SKIP_NOTARIZE=1     Build and sign DMG only; skip notarytool + staple
#
# Output: dist/MenuCue-<CFBundleShortVersionString>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="MenuCue"
CONFIGURATION="Release"
TEAM_ID="${TEAM_ID:-H297ZX38YB}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MenuCue-notary}"
ENTITLEMENTS="$ROOT/Sources/MenuCue.entitlements"
DERIVED="$ROOT/build/DerivedData"
APP_SRC="$DERIVED/Build/Products/${CONFIGURATION}/MenuCue.app"
DIST_DIR="$ROOT/dist"
STAGE_DIR="$ROOT/build/dmg-stage"
VOLUME_NAME="MenuCue"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null || die "$1 not found"
}

resolve_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi
  local identity
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' \
      | head -1
  )"
  [[ -n "${identity}" ]] || die "no Developer ID Application identity in Keychain (import developerID_application.cer)"
  printf '%s\n' "$identity"
}

sign_item() {
  local path="$1"
  local root="$2"
  echo "    codesign: ${path#"${root}/"}"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${IDENTITY}" \
    "${path}"
}

sign_bundle() {
  local path="$1"
  echo "    codesign app: $(basename "${path}")"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" \
    "${path}"
}

# Collect nested signables (Sparkle Updater.app, Autoupdate, XPCs, frameworks).
list_nested_signables() {
  local app="$1"
  local candidate base

  find "${app}/Contents" \( \
    -name '*.xpc' -o \
    -name '*.appex' -o \
    -name '*.framework' -o \
    -name '*.dylib' -o \
    -name '*.app' \
  \) -print 2>/dev/null || true

  # Bare Mach-O helpers inside frameworks (e.g. Sparkle Autoupdate).
  while IFS= read -r candidate; do
    [[ -f "${candidate}" ]] || continue
    base="$(basename "${candidate}")"
    [[ "${base}" == *.* ]] && continue
    if file -b "${candidate}" 2>/dev/null | grep -q 'Mach-O'; then
      printf '%s\n' "${candidate}"
    fi
  done < <(find "${app}/Contents/Frameworks" -type f 2>/dev/null || true)
}

# Sign nested code deepest-first, then the .app itself (avoid relying on --deep).
sign_app() {
  local app="$1"
  local item

  while IFS=$'\t' read -r _ item; do
    [[ -e "${item}" ]] || continue
    [[ "${item}" == "${app}" ]] && continue
    sign_item "${item}" "${app}"
  done < <(
    list_nested_signables "${app}" \
      | awk '!seen[$0]++' \
      | while IFS= read -r item; do
          printf '%08d\t%s\n' "${#item}" "${item}"
        done \
      | sort -r
  )

  sign_bundle "${app}"
}

require_cmd xcodegen
require_cmd xcodebuild
require_cmd codesign
require_cmd hdiutil
require_cmd plutil
require_cmd ditto

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  require_cmd stapler
  xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
    || die "notarytool profile '${NOTARY_PROFILE}' missing — see DISTRIBUTION.md (or set SKIP_NOTARIZE=1)"
fi

IDENTITY="$(resolve_identity)"
echo "==> Signing identity: ${IDENTITY}"
echo "==> Team: ${TEAM_ID}"

echo "==> Building Quick Actions catalog into Resources"
"$ROOT/scripts/build-quick-actions-catalog.sh" \
  "$ROOT/QuickActionsCatalog" \
  "$ROOT/Resources/QuickActionsCatalog"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED}" \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_IDENTITY="${IDENTITY}" \
  CODE_SIGN_STYLE=Manual \
  build

[[ -d "${APP_SRC}" ]] || die "build product missing: ${APP_SRC}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_SRC}/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "${VERSION}" ]] || VERSION="0.0.0"
DMG_NAME="MenuCue-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
TMP_DMG="${ROOT}/build/MenuCue-tmp.dmg"

echo "==> Signing ${APP_SRC}"
sign_app "${APP_SRC}"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_SRC}"
codesign --display --verbose=2 "${APP_SRC}" 2>&1 | head -20

echo "==> Staging DMG contents"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}" "${DIST_DIR}"
ditto "${APP_SRC}" "${STAGE_DIR}/MenuCue.app"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "==> Creating ${DMG_PATH}"
rm -f "${TMP_DMG}" "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDRW \
  "${TMP_DMG}" >/dev/null
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
rm -f "${TMP_DMG}"
rm -rf "${STAGE_DIR}"

echo "==> Signing DMG"
codesign --force --timestamp --sign "${IDENTITY}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "==> SKIP_NOTARIZE=1 — left unsigned-for-Gatekeeper until notarized"
  echo "==> DMG ready (signed, not notarized): ${DMG_PATH}"
  exit 0
fi

echo "==> Submitting to notarytool (profile: ${NOTARY_PROFILE})"
SUBMIT_OUT="$(mktemp)"
# notarytool can exit 0 even when status is Invalid — capture and check.
set +e
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait 2>&1 | tee "${SUBMIT_OUT}"
SUBMIT_RC=${PIPESTATUS[0]}
set -e

if ! grep -Eq 'status: Accepted' "${SUBMIT_OUT}"; then
  SUBMISSION_ID="$(sed -n 's/.*id: *\([0-9a-f-]\{36\}\).*/\1/p' "${SUBMIT_OUT}" | head -1)"
  echo "error: notarization did not succeed (exit ${SUBMIT_RC})" >&2
  if [[ -n "${SUBMISSION_ID}" ]]; then
    echo "==> notarytool log ${SUBMISSION_ID}" >&2
    xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
  fi
  rm -f "${SUBMIT_OUT}"
  exit 1
fi
rm -f "${SUBMIT_OUT}"

echo "==> Stapling"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" || true

echo "==> Done: ${DMG_PATH}"
