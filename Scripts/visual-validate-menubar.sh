#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIAGNOSTICS_PATH="$ROOT_DIR/.derivedData/menubar-visual-diagnostics.json"
APP_EXECUTABLE="$ROOT_DIR/.derivedData/Build/Products/Debug/MenuBarManager.app/Contents/MacOS/MenuBarManager"
DIAGNOSTIC_PROBE_ID="MenuBarManagerDiagnosticProbe.visual.$$.$(date +%s)"
DIAGNOSTIC_DIVIDER_ID="MenuBarManagerHiddenDivider.visual.$$.$(date +%s)"

cd "$ROOT_DIR"

tuist_cmd() {
  if command -v tuist >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 tuist "$@"
  else
    TUIST_SKIP_UPDATE_CHECK=1 mise x tuist@4.194.3 -- tuist "$@"
  fi
}

rm -f "$DIAGNOSTICS_PATH"
pkill -x "MenuBarManager" >/dev/null 2>&1 || true
tuist_cmd generate --no-open

if command -v xcodebuildmcp >/dev/null 2>&1; then
  xcodebuildmcp macos build \
    --workspace-path "$ROOT_DIR/MenuBarManager.xcworkspace" \
    --scheme "MenuBarManager" \
    --configuration Debug \
    --derived-data-path "$ROOT_DIR/.derivedData"
else
  if command -v tuist >/dev/null 2>&1; then
    TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
      -scheme MenuBarManager \
      -configuration Debug \
      -derivedDataPath .derivedData
  else
    TUIST_SKIP_UPDATE_CHECK=1 mise x tuist@4.194.3 -- tuist xcodebuild build \
      -scheme MenuBarManager \
      -configuration Debug \
      -derivedDataPath .derivedData
  fi
fi

MENUBAR_MANAGER_VISUAL_DIAGNOSTICS=1 \
MENUBAR_MANAGER_EXIT_AFTER_DIAGNOSTICS=1 \
MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ITEM=1 \
MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ID="$DIAGNOSTIC_PROBE_ID" \
MENUBAR_MANAGER_DIAGNOSTIC_DIVIDER_ID="$DIAGNOSTIC_DIVIDER_ID" \
MENUBAR_MANAGER_DISABLE_AUTOMATIC_PRIVATE_ITEM_MOVES=1 \
MENUBAR_MANAGER_REPOSITION_CONTROL_ITEM=1 \
MENUBAR_MANAGER_DIAGNOSTICS_PATH="$DIAGNOSTICS_PATH" \
"$APP_EXECUTABLE" >/tmp/MenuBarManager-visual-diagnostics.log 2>&1 &

APP_PID="$!"

for _ in {1..30}; do
  if [[ -f "$DIAGNOSTICS_PATH" ]]; then
    break
  fi
  sleep 0.2
done

wait "$APP_PID" || true

if [[ ! -f "$DIAGNOSTICS_PATH" ]]; then
  echo "Visual diagnostics file was not created." >&2
  cat /tmp/MenuBarManager-visual-diagnostics.log >&2 || true
  exit 1
fi

python3 - "$DIAGNOSTICS_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as file:
    data = json.load(file)

errors = []

if not data.get("isCollapsed"):
    errors.append("diagnostic app did not enter collapsed state")

if not data.get("controlIsInMenuBarSafeArea"):
    errors.append("control item is not in a notch-safe menu bar area")

if not data.get("controlIsRepresentedByRealMenuBarWindow"):
    errors.append("control item is not represented by a real menu bar window")

if data.get("controlWidth", 999) > 64:
    errors.append(f"control item is too wide: {data.get('controlWidth')}")

if data.get("hiddenDividerLength") != 10_000:
    errors.append(f"hidden divider did not expand to 10000: {data.get('hiddenDividerLength')}")

if not data.get("diagnosticProbeIsVisibleWhenExpanded"):
    errors.append("diagnostic probe was not visible before collapse")

if not data.get("diagnosticProbeIsHiddenWhenCollapsed"):
    errors.append("diagnostic probe was not pushed offscreen by collapse")

if data.get("realMenuBarItemCount", 0) <= data.get("visibleRealMenuBarItemCount", 0):
    errors.append("diagnostics did not expose any hidden real menu bar windows")

if not data.get("popoverIsNearControl"):
    errors.append("popover is not anchored near the control item")

if errors:
    print(json.dumps(data, indent=2, sort_keys=True))
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(json.dumps(data, indent=2, sort_keys=True))
PY
