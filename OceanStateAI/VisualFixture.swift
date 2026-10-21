#if DEBUG
import Foundation

extension OceanStore {
    // Synthetic simulator-only layout fixture. Excluded from the release IPA.
    func loadVisualFixture(chat: Bool) {
        connected = true
        models = [ServerModel(id: "preview", name: "OceanState Standard")]
        selectedModel = "preview"
        tools = [ServerTool(id: "computer", name: "PC workspace", detail: "")]
        selectedTools = ["computer"]
        title = "A new project"
        if chat {
            messages = [
                .parse(["id": "user", "role": "user", "content": "Help me plan a new project on my PC."]),
                .parse(["id": "assistant", "role": "assistant", "content": "Let’s build it together. Tell me what you want to create, and I’ll help turn it into a working project.\n\n**Your workspace is ready.** I can inspect files, write code, run checks, and show you the results through your PC tools.\n\nWhat should we make first?", "done": true])
            ]
        }
    }
}
#endif
