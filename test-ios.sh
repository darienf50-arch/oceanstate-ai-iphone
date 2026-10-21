#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if "iPhone" in x["name"]))')
xcodebuild test -project OceanStateAI.xcodeproj -scheme OceanStateAI \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/Simulator \
  -resultBundlePath build/TestResults.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
# XCTest may use a cloned simulator and shut down the requested device afterwards.
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" build/Simulator/Build/Products/Debug-iphonesimulator/OceanStateAI.app
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl launch "$DEVICE_ID" com.oceanstateai.iphone
sleep 3
xcrun simctl io "$DEVICE_ID" screenshot build/NativeConnection.png
xcrun simctl terminate "$DEVICE_ID" com.oceanstateai.iphone
xcrun simctl launch "$DEVICE_ID" com.oceanstateai.iphone --native-welcome-preview
sleep 3
xcrun simctl io "$DEVICE_ID" screenshot build/NativeWelcome.png
xcrun simctl terminate "$DEVICE_ID" com.oceanstateai.iphone
xcrun simctl launch "$DEVICE_ID" com.oceanstateai.iphone --native-chat-preview
sleep 3
xcrun simctl io "$DEVICE_ID" screenshot build/NativeChat.png
