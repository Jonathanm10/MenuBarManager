#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="MenuBarManager"
SCHEME="MenuBarManager"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.derivedData/release}"
PACKAGE_DIR="${PACKAGE_DIR:-$ROOT_DIR/.build/release}"
APP_PATH="$PACKAGE_DIR/$APP_NAME.app"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

usage() {
  cat <<EOF
Usage: $0

Builds a Release app bundle at:
  $APP_PATH

Environment:
  VERSION                                      Marketing version to embed. Default: $VERSION
  BUILD_NUMBER                                 Build number to embed. Default: $BUILD_NUMBER
  CONFIGURATION                                Xcode configuration. Default: Release
  MENUBAR_MANAGER_RELEASE_CODE_SIGN_IDENTITY   Code-signing identity to use after packaging.
  MENUBAR_MANAGER_RELEASE_DISABLE_CODESIGN=1   Leave the bundle unsigned.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tuist_cmd() {
  if command -v tuist >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 tuist "$@"
  elif command -v mise >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 mise x tuist@4.194.3 -- tuist "$@"
  else
    echo "Missing tuist. Install tuist, or install mise so the script can run tuist@4.194.3." >&2
    exit 1
  fi
}

release_signing_identity() {
  if [[ "${MENUBAR_MANAGER_RELEASE_DISABLE_CODESIGN:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -n "${MENUBAR_MANAGER_RELEASE_CODE_SIGN_IDENTITY:-}" ]]; then
    printf "%s\n" "$MENUBAR_MANAGER_RELEASE_CODE_SIGN_IDENTITY"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/"Developer ID Application:/ { print $2; exit }'
}

sign_packaged_app() {
  local identity="$1"

  if [[ "${MENUBAR_MANAGER_RELEASE_DISABLE_CODESIGN:-0}" == "1" ]]; then
    echo "Skipping code signing for $APP_PATH"
    return
  fi

  if [[ -n "$identity" ]]; then
    /usr/bin/codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$identity" \
      "$APP_PATH"
    echo "Signed $APP_PATH with: $identity"
  else
    /usr/bin/codesign --force --deep --sign - "$APP_PATH"
    echo "Ad-hoc signed $APP_PATH"
  fi

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

tuist_cmd generate --no-open
tuist_cmd xcodebuild build \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

BUILT_APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" -maxdepth 1 -name "$APP_NAME.app" -print -quit)"

if [[ -z "$BUILT_APP_PATH" ]]; then
  echo "Could not find built app in $DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$PACKAGE_DIR"
/usr/bin/ditto "$BUILT_APP_PATH" "$APP_PATH"

sign_packaged_app "$(release_signing_identity)"

echo "Packaged $APP_PATH (version $VERSION, build $BUILD_NUMBER)"
