#!/bin/bash
# Renders the panel previews to PNG in light and dark mode, in English and German:
#   scripts/snapshots.sh [folder]     (default: build/snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/snapshots}"
APP="$(scripts/build.sh | tail -1)"
mkdir -p "$OUT"
for LANG_CODE in en de; do
  "$APP/Contents/MacOS/Mixpilot" -MixpilotSnapshots "$(cd "$OUT" && pwd)" -AppleLanguages "($LANG_CODE)"
done
ls "$OUT"
