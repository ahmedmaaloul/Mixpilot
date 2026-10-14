#!/bin/bash
# Records the disk image window layout (scripts/dmg/DS_Store) with Finder: run once, and again
# only when the window design changes. Releases copy the result, so they don't need Finder.
#   scripts/dmg/make-layout.sh path/to/Mixpilot.app
# Finder asks once whether this terminal may control it.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="${1:?Pass the path to a built Mixpilot.app}"
WORK="$(mktemp -d)"
STAGING="$WORK/staging"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/Mixpilot.app"
ln -s /Applications "$STAGING/Applications"
cp scripts/dmg/background.tiff "$STAGING/.background/background.tiff"
hdiutil create -srcfolder "$STAGING" -volname Mixpilot -fs HFS+ -format UDRW -ov -quiet "$WORK/layout.dmg"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/layout.dmg" | awk -F'\t' '/\/Volumes\// {print $NF}')"
[[ "$MOUNT" == "/Volumes/Mixpilot" ]] || { echo "Unexpected mount point: $MOUNT" >&2; exit 1; }

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Mixpilot"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 128
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "Mixpilot.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store asynchronously.
for _ in $(seq 1 20); do [[ -f "$MOUNT/.DS_Store" ]] && break; sleep 0.5; done
sync
cp "$MOUNT/.DS_Store" scripts/dmg/DS_Store
hdiutil detach "$MOUNT" -quiet
rm -rf "$WORK"
echo "✓ scripts/dmg/DS_Store"
