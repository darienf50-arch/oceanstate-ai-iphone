#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild build -project OceanStateAI.xcodeproj -scheme OceanStateAI -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO
python3 - <<'PY'
import json, subprocess, time
def call(*args, timeout=60, check=True):
    return subprocess.run(args, check=check, timeout=timeout)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
device=next(x['udid'] for group in devices['devices'].values() for x in group if 'iPhone' in x['name'])
call('xcrun','simctl','boot',device,check=False)
call('xcrun','simctl','bootstatus',device,'-b',timeout=180)
call('xcrun','simctl','install',device,'build/Simulator/Build/Products/Debug-iphonesimulator/OceanStateAI.app')
call('xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100')
for filename, argument in [('NativeConnection.png',None),('NativeWelcome.png','--native-welcome-preview'),('NativeChat.png','--native-chat-preview')]:
    command=['xcrun','simctl','launch',device,'com.oceanstateai.iphone']
    if argument: command.append(argument)
    call(*command)
    time.sleep(3)
    call('xcrun','simctl','io',device,'screenshot','build/'+filename)
    call('xcrun','simctl','terminate',device,'com.oceanstateai.iphone')
PY
