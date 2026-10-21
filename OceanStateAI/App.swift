import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main
struct OceanStateApp: App {
    @StateObject private var store = OceanStore()
    var body: some Scene {
        WindowGroup {
            OceanRoot().environmentObject(store).tint(.cyan)
                .preferredColorScheme(.dark).task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--native-chat-preview") { store.loadVisualFixture(chat: true); return }
                    if ProcessInfo.processInfo.arguments.contains("--native-welcome-preview") { store.loadVisualFixture(chat: false); return }
                    #endif
                    await store.restore()
                }
        }
    }
}

struct OceanRoot: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.scenePhase) var scenePhase
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showControls = false
    @State private var showStudio = false
    @State private var importFile = false
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showVoice = false
    private let background = Color(red: 0.035, green: 0.055, blue: 0.085)

    var body: some View {
        NavigationStack {
            Group {
                if store.connected { conversation } else { ConnectionView() }
            }
            .background(background)
            .navigationTitle(store.connected ? "Ocean State AI" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.connected {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showHistory = true } label: { Image(systemName: "sidebar.left") }.accessibilityLabel("Conversation history")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation")
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showControls) { ControlsView() }
        .sheet(isPresented: $showStudio) { StudioView() }
        .sheet(isPresented: $showVoice) { VoiceConversationView() }
        .fullScreenCover(isPresented: $showCamera) { CameraCapture { data in Task { await store.attach(data: data, name: "Camera.jpg", mime: "image/jpeg") } } }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await store.importFile(url) } }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            Task {
                do {
                    if let data = try await selected.loadTransferable(type: Data.self) {
                        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw APIError(message: "This photo could not be decoded.") }
                        await store.attach(data: jpeg, name: "Photo.jpg", mime: "image/jpeg")
                    }
                } catch { store.error = error.localizedDescription }
                photo = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.reconnect() } } }
        .alert("Ocean State AI", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(store.models) { model in Button(model.name) { store.selectedModel = model.id } }
                } label: {
                    HStack(spacing: 5) { Text(store.modelName).font(.subheadline.weight(.semibold)).lineLimit(1); Image(systemName: "chevron.down").font(.caption2) }
                }.disabled(store.sending)
                Spacer()
                Button { showControls = true } label: {
                    Label(store.selectedTools.isEmpty ? "Controls" : "\(store.selectedTools.count) \(store.selectedTools.count == 1 ? "tool" : "tools")", systemImage: "slider.horizontal.3").font(.caption)
                }
            }.padding(.horizontal).padding(.vertical, 10)
            if let notice = store.notice {
                HStack { Text(notice).font(.caption); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") } }
                    .padding(10).background(.cyan.opacity(0.09))
            }
            if store.messages.isEmpty { welcome } else { transcript }
        }.safeAreaInset(edge: .bottom, spacing: 0) { composer }
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 55)
                Image(systemName: "water.waves").font(.system(size: 48, weight: .light)).foregroundStyle(.cyan)
                Text("What are we\nbuilding today?").font(.system(size: 35, weight: .semibold, design: .rounded))
                Text("Your models. Your PC. Your workspace.").foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    starter("Build something", detail: "Code, troubleshoot, and work on projects", icon: "chevron.left.forwardslash.chevron.right", prompt: "Help me build a new project. First ask what I want to create and inspect the available workspace tools.")
                    starter("Create an image or video", detail: "Use the creative tools on your PC", icon: "sparkles.rectangle.stack", prompt: "Help me create an image or video using my installed creative tools. Ask what I want to make and check the available tools first.")
                    starter("Research a topic", detail: "Explore, compare, and explain", icon: "globe", prompt: "Help me research a topic. Ask what I want to investigate, then use available sources and cite them.")
                }
                Button("Explore workflows") { showStudio = true }.font(.subheadline)
            }.frame(maxWidth: 680, alignment: .leading).padding(24)
        }
    }
    private func starter(_ title: String, detail: String, icon: String, prompt: String) -> some View {
        Button { store.draft = prompt } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Text(store.title).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 10)
                    ForEach(store.messages) { message in MessageView(message: message) }
                    if store.sending {
                        HStack { ProgressView().controlSize(.small); Text("Working on your PC…").font(.caption).foregroundStyle(.secondary) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 720).padding(.horizontal, 18).padding(.bottom, 18).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if store.sending || store.messages.count > 2 {
                    Button { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Image(systemName: "arrow.down").padding(10).background(.ultraThinMaterial, in: Circle())
                    }.padding(12).accessibilityLabel("Jump to latest message")
                }
            }
            .onChange(of: store.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(store.attachments) { file in
                            HStack { Image(systemName: file.isImage ? "photo" : "doc"); Text(file.name).lineLimit(1); Button { store.attachments.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle.fill") } }
                                .font(.caption).padding(10).background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            if store.uploading { HStack { ProgressView(); Text("Uploading and processing attachment…").font(.caption) } }
            if store.recording { Label("Recording · tap microphone to transcribe", systemImage: "waveform").font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 12) {
                Menu {
                    Button("Attach file", systemImage: "doc.badge.plus") { importFile = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take photo", systemImage: "camera") { showCamera = true } }
                    Button("Voice conversation", systemImage: "waveform") { showVoice = true }
                    Button("Workflow starters", systemImage: "sparkles") { showStudio = true }
                    Button("Tools and controls", systemImage: "slider.horizontal.3") { showControls = true }
                } label: { Image(systemName: "plus").font(.title3).frame(height: 36) }.disabled(store.sending || store.uploading)
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").frame(height: 36) }
                    .disabled(store.sending || store.uploading).accessibilityLabel("Attach photo")
                TextField("Message Ocean State AI", text: $store.draft, axis: .vertical).lineLimit(1...7).padding(.vertical, 8)
                Button { Task { await store.toggleRecording() } } label: {
                    Image(systemName: store.recording ? "stop.circle.fill" : "mic").foregroundStyle(store.recording ? Color.red : Color.gray).frame(height: 36)
                }.disabled(store.busy || store.sending).accessibilityLabel(store.recording ? "Stop recording" : "Record voice message")
                if store.sending {
                    Button { Task { await store.stop() } } label: { Image(systemName: "stop.fill").padding(10).background(.white, in: Circle()).foregroundStyle(.black) }.accessibilityLabel("Stop task")
                } else {
                    Button { Task { await store.send() } } label: { Image(systemName: "arrow.up").fontWeight(.bold).padding(10).background(.cyan, in: Circle()).foregroundStyle(.black) }
                        .disabled(store.uploading || store.recording || store.busy || (store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty)).accessibilityLabel("Send message")
                }
            }.padding(12).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 25))
            Text("Connected to your PC · Responses can make mistakes").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 5).background(background)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var store: OceanStore
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 35)
                Image(systemName: "water.waves").font(.system(size: 52)).foregroundStyle(.cyan)
                Text("Your AI.\nWithin reach.").font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("A native workspace connected to Ocean State AI on your PC.").foregroundStyle(.secondary)
                VStack(spacing: 15) {
                    TextField("HTTPS server address", text: $server).keyboardType(.URL).textContentType(.URL)
                    Divider()
                    TextField("Account email", text: $email).keyboardType(.emailAddress).textContentType(.username)
                    Divider()
                    SecureField("Password", text: $password).textContentType(.password)
                }.textInputAutocapitalization(.never).autocorrectionDisabled().padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                Button {
                    Task { await store.signIn(server: server, email: email, password: password); password = "" }
                } label: {
                    HStack { Spacer(); if store.busy { ProgressView() } else { Text("Connect to Ocean State AI").fontWeight(.semibold) }; Spacer() }.padding(8)
                }.buttonStyle(.borderedProminent).disabled(store.busy || email.isEmpty || password.isEmpty || ServerAddress.parse(server) == nil)
                Text("Use your existing Ocean State AI account. Keep Tailscale connected when accessing your private server. Your password is used to sign in; only the session token is stored in this iPhone’s Keychain.").font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 520).padding(26).frame(maxWidth: .infinity)
        }.onAppear { server = store.serverText }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    @State private var results: [ChatSummary] = []
    @State private var createProject = false
    @State private var projectName = ""
    @State private var renameID: String?
    @State private var renameTitle = ""
    var body: some View {
        NavigationStack {
            List {
                Button("New conversation", systemImage: "square.and.pencil") { store.newConversation(); dismiss() }
                if search.isEmpty {
                    Section("Projects") {
                        ForEach(store.projects) { project in NavigationLink { ProjectView(project: project, closeHistory: { dismiss() }) } label: { Label(project.name, systemImage: "folder") } }
                        Button("New project", systemImage: "folder.badge.plus") { createProject = true }
                    }
                }
                ForEach(search.isEmpty ? store.chats : results) { chat in
                    Button { Task { await store.open(chat.id) }; dismiss() } label: {
                        HStack { Image(systemName: "bubble.left").foregroundStyle(.secondary); Text(chat.title).foregroundStyle(.primary).lineLimit(2); Spacer(); if chat.id == store.chatID { Image(systemName: "checkmark").foregroundStyle(.cyan) } }.padding(.vertical, 6)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { renameID = chat.id; renameTitle = chat.title }
                        Button("Pin / unpin", systemImage: "pin") { change(chat.id, path: "/pin") }
                        Button("Archive", systemImage: "archivebox") { change(chat.id, path: "/archive") }
                    }
                }
                if store.hasMoreChats && search.isEmpty { Button("Load more conversations") { Task { do { try await store.loadChats() } catch { store.error = error.localizedDescription } } } }
            }
            .searchable(text: $search, prompt: "Search all conversations")
            .navigationTitle("Conversations").toolbar { Button("Done") { dismiss() } }
            .refreshable { do { try await store.loadChats(reset: true) } catch { store.error = error.localizedDescription } }
            .task(id: search) {
                guard !search.isEmpty else { results = []; return }
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    var components = URLComponents(); components.queryItems = [URLQueryItem(name: "text", value: search), URLQueryItem(name: "page", value: "1")]
                    let list = try await store.api?.json("/api/v1/chats/search" + (components.string ?? "")) as? [Object] ?? []
                    try Task.checkCancellation()
                    results = list.compactMap { item in guard let id = item["id"] as? String else { return nil }; return ChatSummary(id: id, title: item["title"] as? String ?? "Conversation") }
                } catch is CancellationError {} catch { store.error = error.localizedDescription }
            }
            .alert("New project", isPresented: $createProject) {
                TextField("Project name", text: $projectName)
                Button("Create") { let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; Task { do { try await store.createProject(name); projectName = "" } catch { store.error = error.localizedDescription } } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename conversation", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
                TextField("Title", text: $renameTitle)
                Button("Save") {
                    guard let id = renameID else { return }
                    let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty { change(id, path: "", body: ["chat": ["title": title]]) }
                    renameID = nil
                }
                Button("Cancel", role: .cancel) { renameID = nil }
            }
        }
    }
    private func change(_ id: String, path: String, body: Object? = nil) {
        Task {
            do {
                _ = try await store.api?.json("/api/v1/chats/\(id)\(path)", method: "POST", body: body)
                try await store.loadChats(reset: true)
                if store.chatID == id { await store.reconnect() }
            } catch { store.error = error.localizedDescription }
        }
    }
}

struct ControlsView: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") { Picker("Model", selection: $store.selectedModel) { ForEach(store.models) { Text($0.name).tag($0.id) } } }
                Section {
                    Toggle("Web search", isOn: $store.webSearch)
                    Toggle("Image generation", isOn: $store.imageGeneration)
                    Label("Code execution uses your selected PC tools", systemImage: "chevron.left.forwardslash.chevron.right").font(.caption).foregroundStyle(.secondary)
                    Toggle("Server memory", isOn: $store.memory)
                } header: { Text("Server features") } footer: { Text("These use the features enabled on your server and supported by the selected model. PC coding, video, agency and workspace tools can be selected below.") }
                Section {
                    ForEach(store.tools) { tool in
                        Toggle(isOn: Binding(get: { store.selectedTools.contains(tool.id) }, set: { if $0 { store.selectedTools.insert(tool.id) } else { store.selectedTools.remove(tool.id) } })) {
                            VStack(alignment: .leading, spacing: 4) { Text(tool.name); if !tool.detail.isEmpty { Text(tool.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) } }
                        }
                    }
                    if store.tools.isEmpty { Text("No selectable tools loaded. Refresh the connection in Settings.").foregroundStyle(.secondary) }
                } header: { Text("PC tools") } footer: { Text("Selected tools allow the model to act on your PC using your existing server permissions. Review the tool activity in each reply. Existing server approval rules still apply.") }
                Section("Response preferences") {
                    TextField("Additional instructions", text: $store.systemPrompt, axis: .vertical).lineLimit(3...8)
                    Text("Your server’s model presets may override additional instructions. Instruction precedence is still being verified.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Custom temperature", isOn: $store.useTemperature)
                    if store.useTemperature { Slider(value: $store.temperature, in: 0...2, step: 0.1); Text("Temperature \(store.temperature, specifier: "%.1f")").font(.caption) }
                }
            }.disabled(store.sending).navigationTitle("Tools & controls").toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Server", value: store.api?.base.host ?? "Disconnected")
                Button("Refresh models, tools and history") { Task { do { try await store.loadCatalog(); store.notice = "Connection refreshed." } catch { store.error = error.localizedDescription } } }
                Button("Reconnect to current task") { Task { await store.reconnect() }; dismiss() }
            }
            Section("Audio") { if store.playing { Button("Stop read-aloud") { store.stopAudio() } }; Text("Voice recordings are transcribed on your PC. Read-aloud uses its configured voice service.").font(.footnote) }
            Section("About") {
                LabeledContent("Version", value: "2.0 · Native preview")
                Text("Native SwiftUI interface. Chat, models, tools, attachments and voice connect directly to your existing server APIs. No WebUI pages are embedded.").font(.footnote)
                Text("Realtime voice calls, push notifications, live camera/screen sharing, offline AI, dedicated project/agency dashboards and full feature parity are not yet implemented.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("Sign out", role: .destructive) { store.signOut(); if !store.connected { dismiss() } } }
        }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
    }
}

struct StudioView: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.dismiss) var dismiss
    private let workflows: [(String, String, String)] = [
        ("Image studio", "photo.artframe", "Use my installed image tools to create an image. Ask for the subject, style and dimensions first."),
        ("Video studio", "film", "Use my installed video tools. Ask whether I want text-to-video, image-to-video or editing, then inspect available engines and settings."),
        ("Coding workspace", "laptopcomputer", "Help me develop a project on my PC. Inspect the workspace tools, confirm the project path, and ask for the requirements before changing files."),
        ("Research", "globe", "Research a topic with available search tools, cite sources and distinguish verified facts from assumptions. Ask me for the topic."),
        ("Business agency", "building.2", "Help me with my existing Ocean State agency. Start by reviewing available agency tools and status. Preserve owner approval requirements for external actions."),
        ("Automations", "clock.arrow.circlepath", "Help me set up an automation using my installed scheduling tools. Ask what should happen and when before creating it.")]
    var body: some View {
        NavigationStack {
            List {
                Section { Text("These prepare a conversation with your PC’s AI. Enable the relevant PC tools in Controls, review the prompt, then send it.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(workflows, id: \.0) { item in
                    Button { store.draft = item.2; dismiss() } label: { Label(item.0, systemImage: item.1).padding(.vertical, 10) }
                }
            }.navigationTitle("Workflows").toolbar { Button("Done") { dismiss() } }
        }
    }
}
