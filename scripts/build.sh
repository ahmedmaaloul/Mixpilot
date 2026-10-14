#!/bin/bash
# Builds the Debug app into build/DerivedData (signed with the team in Config/Base.xcconfig).
#   scripts/build.sh            Debug build
#   scripts/build.sh Release    Release build
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Mixpilot.xcodeproj -scheme Mixpilot -configuration "${1:-Debug}" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates -quiet build
echo "build/DerivedData/Build/Products/${1:-Debug}/Mixpilot.app"
