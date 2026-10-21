#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if "iPhone" in x["name"]))')
xcodebuild test -project OceanStateAI.xcodeproj -scheme OceanStateAI \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/Simulator \
  -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO
xcrun simctl launch "$DEVICE_ID" com.oceanstateai.iphone
xcrun simctl io "$DEVICE_ID" screenshot build/NativeConnection.png
