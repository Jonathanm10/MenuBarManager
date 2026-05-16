#!/usr/bin/env bash
set -euo pipefail

pkill -x "MenuBarManager" >/dev/null 2>&1 || true
