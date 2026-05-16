#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIAGNOSTICS_PATH="$ROOT_DIR/.derivedData/menubar-saved-visibility-diagnostics.json"
APP_EXECUTABLE="$ROOT_DIR/.derivedData/Build/Products/Debug/MenuBarManager.app/Contents/MacOS/MenuBarManager"
PROBE_ID="MenuBarManagerDiagnosticProbe.$(uuidgen)"

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
MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ID="$PROBE_ID" \
MENUBAR_MANAGER_DIAGNOSTIC_COLLAPSED=0 \
MENUBAR_MANAGER_DISABLE_AUTOMATIC_PRIVATE_ITEM_MOVES=1 \
MENUBAR_MANAGER_APPLY_DIAGNOSTIC_VISIBILITY_RULES=1 \
MENUBAR_MANAGER_DIAGNOSTIC_ITEM_VISIBILITIES="{\"$PROBE_ID\":\"hidden\"}" \
MENUBAR_MANAGER_DIAGNOSTICS_PATH="$DIAGNOSTICS_PATH" \
"$APP_EXECUTABLE" >/tmp/MenuBarManager-saved-visibility-diagnostics.log 2>&1 &

APP_PID="$!"

for _ in {1..40}; do
  if [[ -f "$DIAGNOSTICS_PATH" ]]; then
    break
  fi
  sleep 0.2
done

wait "$APP_PID" || true

if [[ ! -f "$DIAGNOSTICS_PATH" ]]; then
  echo "Saved visibility diagnostics file was not created." >&2
  cat /tmp/MenuBarManager-saved-visibility-diagnostics.log >&2 || true
  exit 1
fi

PROBE_ID="$PROBE_ID" python3 - "$DIAGNOSTICS_PATH" <<'PY'
import json
import os
import sys

path = sys.argv[1]
probe_id = os.environ["PROBE_ID"]
with open(path, "r", encoding="utf-8") as file:
    data = json.load(file)

errors = []
rules = data.get("savedVisibilityRules", {})
sync = data.get("menuBarSyncDiagnostics", {})
results = sync.get("results", [])
probe_result = next(
    (
        result for result in results
        if result.get("stableID") == probe_id
        and result.get("visibility") == "hidden"
    ),
    None,
)

if rules.get(probe_id) != "hidden":
    errors.append(f"diagnostic saved rule missing or wrong: {rules}")

if sync.get("mode") != "savedItemVisibility":
    errors.append(f"saved visibility sync did not run: {sync}")

if not probe_result:
    errors.append(f"saved visibility result for diagnostic probe missing: {results}")
elif not probe_result.get("succeeded"):
    errors.append(f"saved visibility result for diagnostic probe failed: {probe_result}")

if probe_result and probe_result.get("windowID") not in data.get("hiddenMenuBarWindowIDs", []):
    errors.append(
        "diagnostic probe window was not tracked as hidden: "
        f"{probe_result.get('windowID')} not in {data.get('hiddenMenuBarWindowIDs', [])}"
    )

if not data.get("diagnosticProbeIsVisibleWhenExpanded"):
    errors.append("diagnostic probe was not visible before applying collapse diagnostics")

if data.get("hiddenDividerLength") != 10_000:
    errors.append(f"hidden divider did not expand to 10000: {data.get('hiddenDividerLength')}")

if not data.get("diagnosticProbeIsHiddenWhenCollapsed"):
    errors.append("diagnostic probe was not hidden after saved rule and collapse")

if errors:
    print(json.dumps(data, indent=2, sort_keys=True))
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(json.dumps({
    "probeID": probe_id,
    "savedVisibilityRules": rules,
    "menuBarSyncDiagnostics": sync,
    "hiddenMenuBarWindowIDs": data.get("hiddenMenuBarWindowIDs", []),
    "diagnosticProbeIsHiddenWhenCollapsed": data.get("diagnosticProbeIsHiddenWhenCollapsed"),
}, indent=2, sort_keys=True))
PY
