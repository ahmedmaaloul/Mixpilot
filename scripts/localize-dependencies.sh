#!/bin/sh
# Build phase (after Copy Bundle Resources): fixes the KeyboardShortcuts package's localizations
# inside the built app.
# - Replaces its German strings with ours (Apple's terms, and a placeholder that fits the field).
# - Removes the languages Mixpilot doesn't support, so the recorder never shows another language
#   than the rest of the app.
set -eu
BUNDLE="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/KeyboardShortcuts_KeyboardShortcuts.bundle"
RESOURCES="$BUNDLE/Contents/Resources"
if [ ! -d "$RESOURCES" ]; then
  echo "error: KeyboardShortcuts resources not found at $RESOURCES"
  exit 1
fi
for folder in "$RESOURCES"/*.lproj; do
  case "$(basename "$folder")" in
    en.lproj|de.lproj|Base.lproj) ;;
    *) rm -rf "$folder" ;;
  esac
done
cp "$SRCROOT/Localization/KeyboardShortcuts/de.lproj/Localizable.strings" "$RESOURCES/de.lproj/Localizable.strings"
