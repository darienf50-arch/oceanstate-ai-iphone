# Ocean State AI for iPhone

Native iOS 17+ app shell for your existing Ocean State AI WebUI. Supports iPhone 15 Pro Max. This uses WKWebView, so the server provides the chat interface, models, history and tools. It does not run the models on your phone. Cookies persist in the app's private WebKit data store.

## Current status

Source prepared on Windows; no IPA has been compiled, signed, installed or device-tested. Xcode and the iPhoneOS SDK are required on a Mac. Voice, downloads, file uploads and external authentication must be verified against your actual WebUI on a device; full WebUI feature parity is not yet verified. Native push notifications and background inference are not implemented.

## Build an IPA for a signing tool

Alternatively, place the contents of this folder at the root of a dedicated GitHub repository, including `.github/workflows/build-ios.yml`. In GitHub Actions, select **Build Ocean State AI IPA**, then **Run workflow**. It runs on a hosted Mac and uploads `OceanStateAI-unsigned` as a downloadable artifact. Extract the IPA and sign it with your chosen compatible sideloading tool. GitHub runner usage may consume your account's included minutes or incur charges; check the account's allowance before running. This workflow has been prepared but has not been run or verified on a hosted Mac.

1. Copy this folder to a Mac with Xcode, launch Xcode once and complete its setup.
2. Install XcodeGen (`brew install xcodegen`).
3. Run `bash build-ipa.sh`.
4. The result is `build/OceanStateAI-unsigned.ipa`. It is intentionally unsigned and cannot be installed directly. Use a compatible sideloading/signing tool and your own Apple account to sign and install it. The tool's account requirements and renewal rules apply.

For direct installation using Xcode instead, generate the project with `xcodegen generate`, open `OceanStateAI.xcodeproj`, select your signing team and a unique bundle identifier, connect your phone and choose Run. Enable Developer Mode on the phone when required. A signed distribution IPA requires appropriate Apple provisioning and device registration; use Xcode's Archive and Distribute workflow.

## Connect

Open the app, enter the HTTPS address of your existing WebUI and sign in normally. The address must work from your iPhone with a valid trusted certificate. `localhost` and `127.0.0.1` on the phone refer to the phone, not your PC. For access away from home, use your existing private network or an authenticated HTTPS endpoint. This project does not expose your PC or configure a tunnel. Plain HTTP addresses are currently rejected; if that is your only endpoint, connection setup needs to be completed before this app will be usable.

## Device acceptance checks

Verify login survives app relaunch; open an existing chat; stream a new reply; switch models; upload a photo and file; exercise voice with microphone permission; open generated images/videos and try saving them; test OAuth if used; disconnect and reconnect the network. Compare these behaviors with Safari against the same server. Treat any failed feature as remaining integration work.

Apple distribution reference: https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
