#!/bin/bash
# iOS 26 Fix: Change Strip Style from "all" to "non-global"

cd "$(dirname "$0")"

# Apply to Release configuration
xcrun xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  STRIP_STYLE=non-global \
  clean build \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=NO

echo "✅ iOS 26 Fix Applied: STRIP_STYLE changed to non-global"
