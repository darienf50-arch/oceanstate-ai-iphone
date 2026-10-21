import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class OceanStore: ObservableObject {
    @Published var api: OceanAPI?
    @Published var connected = false
    @Published var busy = false
    @Published var sending = false
    @Published var uploading = false
    @Published var error: String?
    @Published var notice: String?
    @Published var models: [ServerModel] = []
    @Published var tools: [ServerTool] = []
    @Published var chats: [ChatSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var attachments: [Attachment] = []
    @Published var draft = ""
    @Published var chatID: String?
    @Published var title = "New conversation"
    @Published var selectedModel = ""
    @Published var selectedTools = Set<String>()
    @Published var webSearch = false
    @Published var imageGeneration = false
    @Published var codeInterpreter = false
    @Published var systemPrompt = ""
    @Published var temperature = 0.7
    @Published var useTemperature = false
    @Published var recording = false
    @Published var playing = false
    @Published var hasMoreChats = true
    private var page = 1
    private var monitor: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var activeReplyID: String?
    private var requestPending = false
    private var lastChat: Object = [:]
    private let defaults = UserDefaults.standard
    var serverText: String { defaults.string(forKey: "nativeServer") ?? defaults.string(forKey: "serverURL") ?? "" }
    var modelName: String { models.first { $0.id == selectedModel }?.name ?? "Choose model" }

    func restore() async {
        guard let url = ServerAddress.parse(serverText), let token = TokenVault.read(url) else { return }
        api = OceanAPI(base: url, token: token)
        do { _ = try await api?.object("/api/v1/auths/"); try await loadCatalog(); connected = true }
        catch { self.error = error.localizedDescription }
    }
    func signIn(server: String, email: String, password: String) async {
        guard !sending, !requestPending else { error = "Stop the current task before switching accounts."; return }
        guard let url = ServerAddress.parse(server) else { error = "Enter an HTTPS server address without a path, password or query."; return }
        busy = true; defer { busy = false }
        do {
            let candidate = OceanAPI(base: url)
            let auth = try await candidate.object("/api/v1/auths/signin", method: "POST", body: ["email": email, "password": password])
            guard let token = auth["token"] as? String, !token.isEmpty else {
                throw APIError(message: "This account needs an additional authentication step. Native MFA support is not available yet.")
            }
            try TokenVault.save(token, server: url)
            candidate.token = token; api = candidate
            defaults.set(url.absoluteString, forKey: "nativeServer")
            clearConversation(); selectedTools = []; selectedModel = ""
            try await loadCatalog(); connected = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func loadCatalog() async throws {
        guard let api else { return }
        let response = try await api.object("/api/models")
        models = (response["data"] as? [Object] ?? []).compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return ServerModel(id: id, name: $0["name"] as? String ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !models.contains(where: { $0.id == selectedModel }) {
            selectedModel = models.first(where: { $0.id == "oceanstate-standard" })?.id ?? models.first?.id ?? ""
        }
        // A failed tools request is visible; it must not look like a server with no tools.
        do {
            let list = try await api.json("/api/v1/tools/") as? [Object] ?? []
            tools = list.compactMap {
                guard let id = $0["id"] as? String else { return nil }
                return ServerTool(id: id, name: $0["name"] as? String ?? id, detail: ($0["meta"] as? Object)?["description"] as? String ?? "")
            }
            selectedTools.formIntersection(Set(tools.map(\.id)))
        } catch { notice = "Tools could not be loaded: \(error.localizedDescription)" }
        try await loadChats(reset: true)
    }
    func loadChats(reset: Bool = false) async throws {
        guard let api else { return }
        let requestedPage = reset ? 1 : page + 1
        let list = try await api.json("/api/v1/chats/?page=\(requestedPage)&include_pinned=true&include_folders=true") as? [Object] ?? []
        let summaries = list.compactMap { item -> ChatSummary? in
            guard let id = item["id"] as? String else { return nil }
            return ChatSummary(id: id, title: item["title"] as? String ?? "Conversation")
        }
        if reset { chats = summaries } else { chats += summaries.filter { item in !chats.contains { $0.id == item.id } } }
        page = requestedPage; hasMoreChats = list.count >= 60
    }
    func clearConversation() {
        monitor?.cancel(); monitor = nil; messages = []; chatID = nil; title = "New conversation"
        attachments = []; draft = ""; activeReplyID = nil; lastChat = [:]; sending = false; error = nil
    }
    func newConversation() {
        guard !requestPending, !uploading, !recording else { return }
        if sending { notice = "The previous task continues on your PC. Open its conversation to reconnect." }
        clearConversation()
    }
    func open(_ id: String) async {
        guard !requestPending, !uploading, !recording else { return }
        clearConversation(); chatID = id; busy = true; defer { busy = false }
        do { try await refreshChat(id); if sending { startMonitoring(id) } }
        catch { self.error = error.localizedDescription }
    }
    func refreshChat(_ id: String) async throws {
        guard let api else { return }
        let response = try await api.object("/api/v1/chats/\(id)")
        guard chatID == id else { return }
        let chat = response["chat"] as? Object ?? [:]
        lastChat = chat; title = chat["title"] as? String ?? response["title"] as? String ?? "Conversation"
        messages = ChatBranch.messages(chat)
        if let model = (chat["models"] as? [String])?.first, models.contains(where: { $0.id == model }) { selectedModel = model }
        if let ids = chat["tool_ids"] as? [String] { selectedTools = Set(ids).intersection(Set(tools.map(\.id))) }
        sending = messages.last.map { $0.role == "assistant" && !$0.done } ?? false
        if sending { activeReplyID = messages.last?.id }
    }
    func send(parent: String? = nil, replacement: String? = nil, reusedFiles: [Object]? = nil) async {
        guard let api, connected, !sending, !requestPending, !uploading, !selectedModel.isEmpty else { return }
        let text = (replacement ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        requestPending = true; sending = true; error = nil
        let files = reusedFiles ?? attachments.map(\.remote)
        let userID = UUID().uuidString.lowercased(), replyID = UUID().uuidString.lowercased()
        let parentID = replacement == nil ? messages.last?.id : parent
        var user: Object = ["id": userID, "role": "user", "content": text, "files": files,
                            "timestamp": Int(Date().timeIntervalSince1970), "childrenIds": [replyID],
                            "parentId": parentID as Any? ?? NSNull()]
        user["models"] = [selectedModel]
        let placeholder: Object = ["id": replyID, "role": "assistant", "content": "", "done": false, "parentId": userID]
        let before = messages
        let sentChatID = chatID
        var context = messages
        if replacement != nil { context = parentID.flatMap { id in messages.firstIndex { $0.id == id }.map { Array(messages.prefix($0 + 1)) } } ?? [] }
        var payloadMessages: [Object] = context.map { rawMessage($0) }
        payloadMessages.append(["role": "user", "content": MessagePayload.content(text: text, files: files)])
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payloadMessages.insert(["role": "system", "content": systemPrompt], at: 0)
        }
        var params: Object = [:]
        if useTemperature { params["temperature"] = temperature }
        var body: Object = ["model": selectedModel, "messages": payloadMessages, "stream": true,
                            "session_id": "oceanstate-ios-" + UUID().uuidString,
                            "id": replyID, "parent_id": parentID as Any? ?? NSNull(), "user_message": user,
                            "tool_ids": Array(selectedTools), "files": files, "params": params,
                            "features": ["web_search": webSearch, "image_generation": imageGeneration, "code_interpreter": codeInterpreter]]
        if let chatID { body["chat_id"] = chatID }
        messages = context + [.parse(user), .parse(placeholder)]
        activeReplyID = replyID
        do {
            let result = try await api.object("/api/chat/completions", method: "POST", body: body)
            guard let id = result["chat_id"] as? String else { throw APIError(message: "Server did not acknowledge a saved task. Do not resend until you check History.") }
            chatID = id; draft = ""; attachments = []; requestPending = false
            try await refreshChat(id); startMonitoring(id)
            try? await loadChats(reset: true)
        } catch {
            requestPending = false; sending = false
            // A timeout can happen after the server accepted a task. Never retry automatically.
            messages = before
            self.error = "\(error.localizedDescription) Check History before retrying; your PC may have accepted the task."
            chatID = sentChatID
            try? await loadChats(reset: true)
        }
    }
    private func rawMessage(_ message: ChatMessage) -> Object {
        ["role": message.role, "content": MessagePayload.content(text: message.text, files: message.files)]
    }
    func reconnect() async {
        guard let id = chatID else { return }
        do { try await refreshChat(id); if sending { startMonitoring(id) } }
        catch { self.error = error.localizedDescription }
    }
    private func startMonitoring(_ id: String) {
        monitor?.cancel()
        monitor = Task { [weak self] in
            guard let self else { return }
            var failures = 0
            while !Task.isCancelled, self.chatID == id {
                do {
                    try await Task.sleep(for: .seconds(failures == 0 ? 1.2 : 4))
                    try Task.checkCancellation()
                    try await self.refreshChat(id)
                    failures = 0
                    if !self.sending { break }
                } catch is CancellationError { break }
                catch {
                    failures += 1
                    self.notice = "Connection interrupted. Reconnecting to your PC…"
                    if failures >= 5 { self.error = "Could not reconnect. Your PC task may still be running. Use Reconnect or reopen this chat."; break }
                }
            }
        }
    }
    func stop() async {
        guard let api, let id = chatID else { return }
        do {
            _ = try await api.json("/api/tasks/chat/\(id)/stop", method: "POST")
            monitor?.cancel(); sending = false; try await refreshChat(id)
        } catch { self.error = error.localizedDescription }
    }
    func retry(_ message: ChatMessage, text: String? = nil) async {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let userIndex = message.role == "user" ? index : (messages[..<index].lastIndex { $0.role == "user" })
        guard let userIndex else { return }
        let user = messages[userIndex]
        await send(parent: userIndex > 0 ? messages[userIndex - 1].id : nil, replacement: text ?? user.text, reusedFiles: user.files)
    }
    func attach(data: Data, name: String, mime: String) async {
        guard let api, !uploading, !sending else { return }
        guard data.count <= 25 * 1024 * 1024 else { error = "Choose a file smaller than 25 MB."; return }
        uploading = true; defer { uploading = false }
        do {
            let record = try await api.upload(data, name: name, mime: mime)
            guard let id = record["id"] as? String else { throw APIError(message: "The uploaded file has no ID.") }
            var remote: Object = ["id": id, "name": name, "type": "file", "file": record,
                                  "url": api.base.absoluteString + "/api/v1/files/\(id)/content"]
            if mime.hasPrefix("image/") { remote["type"] = "image"; remote["content_type"] = mime }
            attachments.append(Attachment(id: id, name: name, mime: mime, remote: remote))
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let attrs = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            guard (attrs.fileSize ?? 0) <= 25 * 1024 * 1024 else { throw APIError(message: "Choose a file smaller than 25 MB.") }
            let data = try Data(contentsOf: url)
            await attach(data: data, name: url.lastPathComponent, mime: attrs.contentType?.preferredMIMEType ?? "application/octet-stream")
        } catch { self.error = error.localizedDescription }
    }
    func toggleRecording() async {
        if recording {
            recorder?.stop(); recording = false
            guard let url = recordingURL, let api else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            busy = true; defer { busy = false }
            do {
                let result = try await api.upload(Data(contentsOf: url), name: "voice.m4a", mime: "audio/mp4", transcription: true)
                guard let text = result["text"] as? String else { throw APIError(message: "No transcription returned.") }
                draft += (draft.isEmpty ? "" : "\n") + text
            } catch { self.error = error.localizedDescription }
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else { error = "Allow microphone access in iPhone Settings to record voice."; return }
        do {
            player?.stop(); playing = false
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audio.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder?.record(forDuration: 120) == true else { throw APIError(message: "Recording could not start.") }
            recordingURL = url; recording = true
        } catch { self.error = error.localizedDescription }
    }
    func speak(_ text: String) async {
        guard let api else { return }
        do {
            let data = try await api.speech(text)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data); player?.play(); playing = true
        } catch { self.error = error.localizedDescription }
    }
    func stopAudio() { player?.stop(); playing = false }
    func signOut() {
        guard !sending, !requestPending else { error = "Stop the current task or open a new conversation before signing out."; return }
        if let api { try? TokenVault.save(nil, server: api.base) }
        clearConversation(); connected = false; api = nil; chats = []; tools = []; models = []
    }
}
