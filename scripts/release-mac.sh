#!/bin/bash
# Builds Mixpilot as a signed, notarized disk image for the website (mixpilot.blitzraum.com):
#   build/release/Mixpilot-<version>.dmg
#
# Needs (already set up for Handpilot, same team):
#   - the "Developer ID Application" certificate of team NSRXRUC9KF in the Keychain;
#   - notarization credentials in the Keychain under the profile "handpilot" (not app-specific):
#       xcrun notarytool store-credentials handpilot --apple-id <Apple ID> --team-id NSRXRUC9KF
#
# Usage:
#   scripts/release-mac.sh          release build: Developer ID, notarized and stapled
#   scripts/release-mac.sh --test   same steps with the development certificate, no notarization
#                                   (checks the pipeline; the result only opens on this Mac)
#
# Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in Config/Base.xcconfig first.
# Another notarization profile: NOTARY_PROFILE=<name> scripts/release-mac.sh

set -euo pipefail
cd "$(dirname "$0")/.."

TEST=false
[[ "${1:-}" == "--test" ]] && TEST=true

PROFILE="${NOTARY_PROFILE:-handpilot}"
OUT="build/release"
setting() { sed -n "s/^$1 *= *//p" Config/Base.xcconfig | head -1; }
TEAM="$(setting DEVELOPMENT_TEAM)"
VERSION="$(setting MARKETING_VERSION)"
DMG="$OUT/Mixpilot-$VERSION.dmg"

if [[ -z "$TEAM" ]]; then
  echo "Set DEVELOPMENT_TEAM in Config/Base.xcconfig first." >&2
  exit 1
fi

if [[ $TEST == false ]] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No notarization credentials named \"$PROFILE\" in the Keychain. Run once:" >&2
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM" >&2
  exit 1
fi

echo "▸ Checking strings and tests"
python3 Localization/localize.py
(cd MixpilotKit && swift test -q)

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving Mixpilot $VERSION"
xcodebuild -project Mixpilot.xcodeproj -scheme Mixpilot -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/Mixpilot.xcarchive" \
  -allowProvisioningUpdates -quiet archive

echo "▸ Exporting"
METHOD=$([[ $TEST == true ]] && echo debugging || echo developer-id)
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/Mixpilot.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" \
  -allowProvisioningUpdates -quiet
APP="$OUT/export/Mixpilot.app"
codesign --verify --deep --strict "$APP"
# Hardened runtime is required for notarization.
SIGNATURE="$(codesign -dv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"(runtime)"* ]] || { echo "Hardened runtime missing" >&2; exit 1; }

echo "▸ Creating the disk image"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Mixpilot" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"

if [[ $TEST == true ]]; then
  echo "✓ Test build: $DMG (development signature, not notarized)"
  exit 0
fi

echo "▸ Signing the disk image"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Checking that Gatekeeper accepts it"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
spctl --assess --type execute --verbose "$APP"

echo "✓ Ready to publish: $DMG"
echo "  Upload it to mixpilot.blitzraum.com (Vercel) as the download."
