#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodebuild >/dev/null || { echo 'Run this on macOS with Xcode installed.'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen'; exit 1; }
xcodegen generate
pod install --repo-update
mkdir -p build/Payload
xcodebuild -workspace OceanStateAI.xcworkspace -scheme OceanStateAI -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
ditto build/DerivedData/Build/Products/Release-iphoneos/OceanStateAI.app build/Payload/OceanStateAI.app
cp 'Pods/Target Support Files/Pods-OceanStateAI/Pods-OceanStateAI-acknowledgements.plist' build/Payload/OceanStateAI.app/ThirdPartyNotices.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/Payload/OceanStateAI.app/Info.plist
test -f build/Payload/OceanStateAI.app/OceanStateAI
file build/Payload/OceanStateAI.app/OceanStateAI | grep -q arm64
(cd build && zip -qry OceanStateAI-unsigned.ipa Payload)
unzip -t build/OceanStateAI-unsigned.ipa
echo 'Created build/OceanStateAI-unsigned.ipa. This must be signed by your sideloading tool before installation.'
