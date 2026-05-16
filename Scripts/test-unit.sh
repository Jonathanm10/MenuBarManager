#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.derivedData"
TEST_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/MenuBarManagerTests.xctest"

cd "$ROOT_DIR"

tuist_cmd() {
  if command -v tuist >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 tuist "$@"
  else
    TUIST_SKIP_UPDATE_CHECK=1 mise x tuist@4.194.3 -- tuist "$@"
  fi
}

tuist_cmd generate --no-open
xcodebuild \
  -workspace MenuBarManager.xcworkspace \
  -scheme MenuBarManager \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS,arch=arm64' \
  -skip-testing:MenuBarManagerUITests \
  build-for-testing

xcrun xctest "$TEST_BUNDLE"
