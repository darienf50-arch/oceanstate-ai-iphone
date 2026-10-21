# Native client verification

Version 2 is a native preview. No physical iPhone acceptance test has been completed by the developer.

| Capability | Implemented | Evidence / limits |
| --- | --- | --- |
| Native interface, app icon | Yes | Device build and simulator screenshots; no embedded browser |
| Account sign-in and secure token storage | Yes | API schema inspection, Keychain implementation; real account login still needs iPhone testing |
| Model/tool catalogs | Yes | Authenticated live catalogs read successfully |
| New chats, progressive output, follow-ups | Yes | Live backend task acknowledgements and saved replies |
| Edit/regenerate branches | Yes | Live test preserved alternate replies and selected the new branch |
| Stop and reconnect | Yes | Live stop endpoint terminated a task; reconnect reads saved server state |
| PC tool execution and visible results | Yes | Read-only `project_preview` call executed and its output was persisted |
| Code execution | Through PC tools | Browser-based Pyodide is disabled in native requests because it requires a WebUI browser callback |
| Tool approval/rejection | Yes | Native per-call review UI and inspected server resolution schema; approval/rejection needs end-to-end iPhone testing |
| Structured questions | Yes | Live answer submission persisted and model continuation completed |
| Document attachment | Yes | Live upload and processing passed; native file picker needs device testing |
| Photo attachment and understanding | Yes | Authenticated upload/download and live red-square image understanding passed |
| Native camera capture | Yes | Compiles; physical camera not tested |
| Voice transcription and read-aloud | Yes | Live speech, transcription and the iPhone AAC/M4A format passed; iPhone permissions/playback not tested |
| Turn-based voice conversation | Yes | Native record/transcribe/send/playback state flow implemented; physical microphone/speaker loop not tested |
| Server-wide search, project grouping, saved preferences | Yes | Live endpoints and preservation of existing history passed |
| Project instructions and knowledge | Partial | Project instruction reached request context but a simple adherence check failed; do not rely on it yet |
| Additional per-chat instructions | Partial | Submitted and saved; preset precedence is still being verified |
| Image/video generation, research, PC coding, agency, schedules | Through existing server tools | Native tool selection and chat can invoke installed capabilities; each workflow has not been tested from an iPhone |
| Generated media and document previews | Yes | Authenticated fetching, native image view and Quick Look implemented; all generated formats not tested |
| Custom Markdown, code copy, message sharing | Yes | Native renderers compile; text and chat layout visually inspected |
| Realtime full-duplex voice, live screen/camera sharing | No | Separate work |
| Push notifications, interactive artifacts, native IDE/terminal, agency dashboards | No | Separate work |
| OAuth/MFA login, offline AI, complete ChatGPT/WebUI parity | No | Not claimed |

Client tests cover selected-branch reconstruction, history cycles, legacy chats, structured output text, URL validation, credential origin isolation and multimodal photo payloads. Simulator screenshots use synthetic debug-only fixtures, excluded from the release IPA. Server tests used clearly labeled native QA conversations and synthetic attachments; no customer messages were sent or public server access enabled.
