#!/bin/bash
# Builds and (re)starts the Debug app. Extra arguments go to the app, for example:
#   scripts/run.sh -AppleLanguages "(de)"
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(scripts/build.sh | tail -1)"
pkill -x Mixpilot 2>/dev/null && sleep 0.5 || true
open -n "$APP" --args "$@"
echo "Running $APP $*"
