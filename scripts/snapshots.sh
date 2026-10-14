#!/bin/bash
# Renders the panel previews to PNG in light and dark mode, in English and German:
#   scripts/snapshots.sh [folder]     (default: build/snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/snapshots}"
APP="$(scripts/build.sh | tail -1)"
mkdir -p "$OUT"
# Through Launch Services (`open`), so Mixpilot is the active app (controls draw active) and macOS
# checks its own permissions rather than the terminal's. A few windows flash on screen meanwhile.
for LANG_CODE in en de; do
  open -W -n "$APP" --args -MixpilotSnapshots "$(cd "$OUT" && pwd)" -AppleLanguages "($LANG_CODE)"
done
ls "$OUT"
