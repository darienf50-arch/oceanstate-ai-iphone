# Ocean State AI — native iPhone client

A SwiftUI iPhone workspace for a PC-hosted Ocean State AI installation. Version 2 replaces the original WKWebView wrapper. It contains no WebKit view, browser shell, or embedded WebUI pages. Existing backend APIs are reused to preserve models, conversations, files, tools and local voice services; this client still depends on those server APIs. Models continue running on the PC, not on the iPhone.

## Implemented

- Native chat with Markdown text, code blocks with copy, photo/generated-image previews, tool activity, attachment preview/share, message copy/share and server errors.
- Model selection, selectable PC tools, search/image/code/memory controls, additional instructions and optional temperature.
- Server-saved conversations, server search, paginated history, project folders and project conversations.
- Edit/regenerate creates a branch while preserving previous replies. Native preferences are saved with the conversation.
- Photos, native camera and document attachments (25 MB input limit). Documents use server processing; images use multimodal input.
- Microphone recording and PC transcription, PC speech playback and turn-based voice conversation with interruption controls. This is not full-duplex realtime voice.
- Backend task acknowledgements, progressive polling of saved output, stop, reconnect and resume after reopening a running chat. PC execution can continue while iOS suspends the client. Background UI updates and notifications are not implemented.
- Tool approval/rejection and structured answers to the server's `ask_user` questions. Existing owner approval rules remain server-side; the agent cannot approve business actions on the owner's behalf.
- HTTPS-only connection, native email/password sign-in, origin-bound tokens in iPhone Keychain, no saved password and no bearer token on external media URLs or cross-origin redirects.

## Remaining work

Known compatibility issue: project instructions were present in the server request context, but the selected presets did not follow a simple instruction check. Project grouping works; project knowledge and instruction precedence are not verified. Treat additional per-chat instructions as best effort until server prompt handling is resolved.

This is a native preview, not complete ChatGPT or WebUI feature parity. Dedicated PC filesystem/editor/terminal screens, agency/CRM and automation dashboards, memory management, interactive artifacts, realtime voice, live camera/screen sharing, push notifications, OAuth/MFA flows and offline AI remain to be implemented. Server tools can expose PC coding, media, business and scheduling capabilities through chat; workflow cards prepare prompts, not completed jobs. Browser-only tools requiring callbacks into a WebUI browser session are not supported.

Image/video generation and research depend on server providers and model capabilities. Compiling an app and testing APIs does not establish generation quality or physical iPhone behavior. Do not claim those features were device-tested until acceptance checks have been completed.

## Build and verification

On a Mac with Xcode and XcodeGen (`brew install xcodegen`):

```sh
bash build-ipa.sh
bash test-ios.sh
```

The IPA is `build/OceanStateAI-unsigned.ipa`. It is not directly installable; sign it using your own compatible sideloading tool/account. Using the same signing identity and bundle identifier allows an in-place update. Free-account provisioning normally needs periodic renewal. Never put Apple passwords in chat, commits or workflow secrets.

The manually triggered GitHub Actions workflow uses a standard `macos-latest` runner in this public repository. It builds an arm64 IPA, validates its ZIP, runs native client tests on an iPhone simulator and exports a screenshot and XCTest results. Standard hosted compute is free for public repositories; private repositories and other runner types have separate billing. No signing credentials, server data or model weights belong in this repository.

## Connection and server integration

Enter your PC's reachable HTTPS origin and sign in using your existing Ocean State account. A previous wrapper's saved address can be reused. The PC must be online. For a Tailscale-only server, connect Tailscale on the iPhone first. `localhost` refers to the iPhone, not the PC. This client creates no public network route.

Native requests identify themselves as `OceanStateAI-iOS/2`. On the owner's installation, a narrowly scoped server filter update respects native preferences while retaining previous WebUI defaults. This is a preference signal, not authentication; normal server authorization applies. Other installations that force features/tools on need equivalent preference handling for the controls to be authoritative.

APIs used: `/api/v1/auths/signin`, `/api/models`, `/api/v1/tools/`, `/api/v1/chats/`, `/api/chat/completions`, `/api/tasks/chat/{id}/stop`, `/api/v1/files/`, `/api/v1/folders/`, `/api/v1/audio/transcriptions`, `/api/v1/audio/speech` and per-message tool-call resolution. Generation is acknowledged as a backend task and observed through saved chat output. The client never automatically resends an uncertain request after a timeout.

## Physical iPhone acceptance checks

Sign in and relaunch; open history; change models; send a new chat and follow-up; edit/regenerate and confirm branch preservation; attach a document, library photo and camera image; verify image understanding; record a voice message; test read-aloud and turn-based voice; enable a read-only PC tool and inspect its result; exercise a question and approval; stop a task; lock/unlock and reconnect; inspect generated images/video; verify project context and sharing. Test network loss after send without blindly retrying. Keep WebUI available separately for unsupported workflows.
