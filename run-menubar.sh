#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MenuBarManager"
SCHEME="MenuBarManager"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.derivedData"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP_PATH="$INSTALL_DIR/$APP_NAME.app"
BUNDLE_ID="com.jonathan.MenuBarManager"
RUN_DOCTOR=0
SKIP_BUILD=0

usage() {
  cat <<EOF
Usage: $0 [--skip-build] [--doctor]

Builds, installs, signs, and launches $APP_NAME from one stable app path:
  $INSTALLED_APP_PATH

Options:
  --skip-build  Relaunch the already-installed app without rebuilding.
  --doctor      Print permission/signing diagnostics after launch.

Environment:
  MENUBAR_MANAGER_CODE_SIGN_IDENTITY  Code-signing identity to use.
  MENUBAR_MANAGER_DISABLE_CODESIGN=1  Keep ad-hoc signing for this run.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --doctor)
      RUN_DOCTOR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

tuist_cmd() {
  if command -v tuist >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 tuist "$@"
  else
    TUIST_SKIP_UPDATE_CHECK=1 mise x tuist@4.194.3 -- tuist "$@"
  fi
}

code_sign_identity() {
  if [[ "${MENUBAR_MANAGER_DISABLE_CODESIGN:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -n "${MENUBAR_MANAGER_CODE_SIGN_IDENTITY:-}" ]]; then
    printf "%s\n" "$MENUBAR_MANAGER_CODE_SIGN_IDENTITY"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/"Apple Development:/ { print $2; exit }'
}

sign_installed_app() {
  local identity="$1"

  if [[ -z "$identity" ]]; then
    echo "WARNING: no Apple Development code-signing identity found." >&2
    echo "WARNING: using the ad-hoc build; macOS privacy permissions may reset after rebuilds." >&2
    return
  fi

  /usr/bin/codesign --force --deep --sign "$identity" "$INSTALLED_APP_PATH"
  echo "Signed $INSTALLED_APP_PATH with: $identity"
  /usr/bin/codesign -dr - "$INSTALLED_APP_PATH" 2>&1 | sed 's/^/  /'
}

launch_installed_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  open -n "$INSTALLED_APP_PATH" --args --reveal-on-launch
  echo "Launched $INSTALLED_APP_PATH"
}

if [[ "$SKIP_BUILD" == "0" ]]; then
  tuist_cmd generate --no-open
  tuist_cmd xcodebuild build \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH"

  APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" -maxdepth 1 -name "$APP_NAME.app" -print -quit)"

  if [[ -z "$APP_PATH" ]]; then
    echo "Could not find built app in $DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP_PATH"
  ditto "$APP_PATH" "$INSTALLED_APP_PATH"
  sign_installed_app "$(code_sign_identity)"
elif [[ ! -d "$INSTALLED_APP_PATH" ]]; then
  echo "Missing installed app at $INSTALLED_APP_PATH. Run without --skip-build first." >&2
  exit 1
fi

launch_installed_app

if [[ "$RUN_DOCTOR" == "1" ]]; then
  "$ROOT_DIR/Scripts/doctor-permissions.sh" --app "$INSTALLED_APP_PATH" --bundle-id "$BUNDLE_ID"
else
  echo "Verify macOS permission identity with ./Scripts/doctor-permissions.sh"
fi
