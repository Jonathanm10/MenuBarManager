#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="MenuBarManager"
PACKAGE_DIR="${PACKAGE_DIR:-$ROOT_DIR/.build/release}"
APP_PATH="${APP_PATH:-$PACKAGE_DIR/$APP_NAME.app}"
VERSION="${VERSION:-0.1.0}"
RELEASE_DIR="${RELEASE_DIR:-$ROOT_DIR/release}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"
OUTPUT_DMG="${OUTPUT_DMG:-$RELEASE_DIR/$APP_NAME-$VERSION.dmg}"
STABLE_OUTPUT_DMG="${STABLE_OUTPUT_DMG:-$RELEASE_DIR/$APP_NAME.dmg}"
SKIP_PACKAGE="${SKIP_PACKAGE:-0}"

usage() {
  cat <<EOF
Usage: $0

Creates a compressed DMG containing $APP_NAME.app and an Applications shortcut:
  $OUTPUT_DMG

Environment:
  VERSION             Version used in the DMG filename. Default: $VERSION
  OUTPUT_DMG          Full output DMG path. Default: $OUTPUT_DMG
  STABLE_OUTPUT_DMG   Optional stable copy path. Default: $STABLE_OUTPUT_DMG
  SKIP_PACKAGE=1      Reuse the app bundle in $APP_PATH instead of running package_app.sh.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$SKIP_PACKAGE" != "1" ]]; then
  VERSION="$VERSION" "$ROOT_DIR/Scripts/package_app.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  echo "Run Scripts/package_app.sh first, or leave SKIP_PACKAGE unset." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
SOURCE_DIR="$STAGING_DIR/source"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$SOURCE_DIR" "$RELEASE_DIR"
/usr/bin/ditto "$APP_PATH" "$SOURCE_DIR/$APP_NAME.app"
ln -s /Applications "$SOURCE_DIR/Applications"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -quiet \
  -srcfolder "$SOURCE_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG" >/dev/null

if [[ -n "$STABLE_OUTPUT_DMG" && "$STABLE_OUTPUT_DMG" != "$OUTPUT_DMG" ]]; then
  cp "$OUTPUT_DMG" "$STABLE_OUTPUT_DMG"
fi

echo "Created $OUTPUT_DMG"
