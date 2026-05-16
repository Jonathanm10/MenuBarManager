#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MenuBarManager"
APP_PATH="${MENUBAR_MANAGER_APP_PATH:-$HOME/Applications/$APP_NAME.app}"
BUNDLE_ID="${MENUBAR_MANAGER_BUNDLE_ID:-com.jonathan.MenuBarManager}"
OPEN_SETTINGS=0
RESET_TCC=0

usage() {
  cat <<EOF
Usage: $0 [--app /path/to/MenuBarManager.app] [--bundle-id id] [--open-settings] [--reset-tcc]

Checks the app identity macOS privacy settings should use:
  - installed app path
  - bundle identifier
  - code-signing requirement
  - running executable path
  - visible TCC rows for Screen Recording and Accessibility

Default app path: $APP_PATH
Default bundle id: $BUNDLE_ID
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --open-settings)
      OPEN_SETTINGS=1
      shift
      ;;
    --reset-tcc)
      RESET_TCC=1
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

section() {
  printf "\n== %s ==\n" "$1"
}

plist_value() {
  local key="$1"
  local plist="$APP_PATH/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

section "Expected identity"
echo "Repository: $ROOT_DIR"
echo "App path:   $APP_PATH"
echo "Bundle id:  $BUNDLE_ID"

section "Installed app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app at $APP_PATH"
  echo "Run ./run-menubar.sh first so Settings has one stable app bundle to authorize."
else
  actual_bundle_id="$(plist_value CFBundleIdentifier)"
  executable="$(plist_value CFBundleExecutable)"
  display_name="$(plist_value CFBundleDisplayName)"

  echo "Display name: ${display_name:-<missing>}"
  echo "Bundle id:    ${actual_bundle_id:-<missing>}"
  echo "Executable:   ${executable:-<missing>}"

  if [[ "$actual_bundle_id" != "$BUNDLE_ID" ]]; then
    echo "WARNING: installed bundle id does not match expected bundle id."
  fi

  if command -v codesign >/dev/null 2>&1; then
    echo
    echo "Code signature:"
    codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
      | awk '/Identifier=|TeamIdentifier=|Authority=|CodeDirectory v=|Sealed Resources/ { print "  " $0 }' \
      || true

    echo
    echo "Designated requirement:"
    codesign -dr - "$APP_PATH" 2>&1 | sed 's/^/  /' || true
  fi
fi

section "Running process"
pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
if [[ -z "$pids" ]]; then
  echo "No running $APP_NAME process."
else
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    command_path="$(ps -ww -p "$pid" -o comm= 2>/dev/null || true)"
    command_line="$(ps -ww -p "$pid" -o command= 2>/dev/null || true)"
    echo "PID $pid"
    echo "  executable: ${command_path:-<unknown>}"
    echo "  command:    ${command_line:-<unknown>}"

    if [[ -n "$command_path" && "$command_path" != "$APP_PATH/Contents/MacOS/$APP_NAME" ]]; then
      echo "  WARNING: running executable is not the expected installed app."
    fi
  done <<< "$pids"
fi

section "Other copies with same bundle id"
if command -v mdfind >/dev/null 2>&1; then
  copies="$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)"
  if [[ -z "$copies" ]]; then
    echo "Spotlight found no app bundles for $BUNDLE_ID."
  else
    echo "$copies" | sed 's/^/  /'
  fi
else
  echo "mdfind is not available."
fi

section "TCC database rows"
escaped_bundle_id="$(sql_quote "$BUNDLE_ID")"
escaped_app_name="$(sql_quote "$APP_NAME")"

query_tcc_db() {
  local label="$1"
  local tcc_db="$2"

  echo "$label: $tcc_db"
  if [[ ! -r "$tcc_db" ]]; then
    echo "  Cannot read this database."
    return
  fi

  exact_rows="$(
    sqlite3 -readonly -header -column "$tcc_db" "
    SELECT
      service,
      client,
      client_type,
      auth_value,
      auth_reason,
      datetime(last_modified, 'unixepoch', 'localtime') AS last_modified
    FROM access
    WHERE client = '$escaped_bundle_id'
      AND service IN ('kTCCServiceScreenCapture', 'kTCCServiceAccessibility')
    ORDER BY service;
  " 2>/dev/null || true
  )"

  if [[ -n "$exact_rows" ]]; then
    echo "$exact_rows"
  else
    echo "  No exact rows for $BUNDLE_ID."
  fi

  nearby_rows="$(
    sqlite3 -readonly -header -column "$tcc_db" "
    SELECT
      service,
      client,
      client_type,
      auth_value,
      auth_reason,
      datetime(last_modified, 'unixepoch', 'localtime') AS last_modified
    FROM access
    WHERE (
        client LIKE '%$escaped_bundle_id%'
        OR client LIKE '%$escaped_app_name%'
      )
      AND service IN ('kTCCServiceScreenCapture', 'kTCCServiceAccessibility')
      AND client != '$escaped_bundle_id'
    ORDER BY service, client;
  " 2>/dev/null || true
  )"

  if [[ -n "$nearby_rows" ]]; then
    echo
    echo "  Nearby path/name rows:"
    echo "$nearby_rows"
  fi
}

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is not available."
else
  query_tcc_db "User TCC" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  echo
  query_tcc_db "System TCC" "/Library/Application Support/com.apple.TCC/TCC.db"
  echo
  echo "auth_value is usually 2 for allowed and 0 for denied."
  echo "No row means macOS has not recorded an allow/deny decision for that exact client."
fi

if [[ "$RESET_TCC" == "1" ]]; then
  section "Resetting TCC"
  echo "Resetting Screen Recording and Accessibility for $BUNDLE_ID"
  tccutil reset ScreenCapture "$BUNDLE_ID" || true
  tccutil reset Accessibility "$BUNDLE_ID" || true
  echo "Relaunch the app, grant permissions again, then restart it once more."
fi

if [[ "$OPEN_SETTINGS" == "1" ]]; then
  section "Opening Settings"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi
