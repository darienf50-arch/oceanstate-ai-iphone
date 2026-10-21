import SwiftUI
import QuickLook

struct PreviewFile: Identifiable { let id = UUID(); let url: URL }

struct MessageView: View {
    @EnvironmentObject var store: OceanStore
    let message: ChatMessage
    @State private var editing = false
    @State private var editedText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: message.role == "user" ? "person.crop.circle" : "water.waves").foregroundStyle(message.role == "user" ? .secondary : .cyan)
                Text(message.role == "user" ? "You" : "Ocean State AI").font(.subheadline.weight(.semibold))
                Spacer()
                if !message.done { Text("In progress").font(.caption2).foregroundStyle(.cyan) }
            }
            if !message.text.isEmpty { NativeMarkdown(text: message.text) }
            if !message.files.isEmpty {
                ForEach(Array(message.files.enumerated()), id: \.offset) { _, file in
                    if let url = file["url"] as? String {
                        RemoteAttachment(source: url, name: file["name"] as? String ?? "Attachment", image: (file["type"] as? String) == "image")
                    }
                }
            }
            if !message.tools.isEmpty {
                DisclosureGroup("Tool activity · \(message.tools.count)") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(message.tools.enumerated()), id: \.offset) { _, tool in ToolActivity(tool: tool, message: message) }
                    }.padding(.top, 8)
                }.font(.caption).padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = message.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let sources = message.raw["sources"] as? [Object], !sources.isEmpty {
                DisclosureGroup("Sources") {
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        let detail = source["source"] as? Object ?? source
                        Text(detail["name"] as? String ?? detail["id"] as? String ?? "Source").font(.caption).textSelection(.enabled)
                    }
                }.font(.caption)
            }
            if !message.text.isEmpty {
                HStack(spacing: 20) {
                    Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy message")
                    ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share message")
                    if message.role == "assistant" {
                        Button { Task { await store.speak(message.text) } } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Read aloud")
                        Button { Task { await store.retry(message) } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.sending).accessibilityLabel("Regenerate as a new branch")
                    } else {
                        Button { editedText = message.text; editing = true } label: { Image(systemName: "pencil") }.disabled(store.sending).accessibilityLabel("Edit and branch")
                    }
                }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
            }
        }
        .padding(message.role == "user" ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == "user" ? Color.white.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack { TextEditor(text: $editedText).padding(); Text("Sending an edit creates a new branch. The previous branch stays on the server.").font(.caption).foregroundStyle(.secondary).padding() }
                    .navigationTitle("Edit message")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Send") { editing = false; Task { await store.retry(message, text: editedText) } }.disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
            }
        }
    }
}

struct ToolActivity: View {
    @EnvironmentObject var store: OceanStore
    let tool: Object
    let message: ChatMessage
    @State private var confirming = false
    @State private var resolving = false
    private var callID: String { tool["call_id"] as? String ?? tool["id"] as? String ?? "" }
    private var result: Object? { message.output.first { ($0["type"] as? String) == "function_call_output" && ($0["call_id"] as? String) == callID } }
    private var pending: Bool { ["pending", "requires_approval"].contains(tool["status"] as? String ?? "") && result == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tool["name"] as? String ?? "Tool", systemImage: result == nil ? "gearshape.2" : "checkmark.circle")
                .font(.caption.weight(.semibold))
            Text(tool["status"] as? String ?? "").font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Arguments") { Text(formatted(tool["arguments"])).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            if let result { DisclosureGroup("Result") { Text(formatted(result["output"])).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
            if pending {
                HStack {
                    Button("Review & approve") { confirming = true }.buttonStyle(.borderedProminent)
                    Button("Reject", role: .destructive) { resolve("reject") }.buttonStyle(.bordered)
                }.disabled(resolving)
            }
        }
        .confirmationDialog("Allow this tool call on your PC? Review its arguments before approving.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Approve this call") { resolve("approve") }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func resolve(_ action: String) {
        guard let api = store.api, let id = store.chatID, !callID.isEmpty else { return }
        resolving = true
        Task {
            defer { resolving = false }
            do {
                _ = try await api.object("/api/v1/chats/\(id)/messages/\(message.id)/resolve", method: "POST", body: ["call_id": callID, "action": action])
                await store.reconnect()
            } catch { store.error = error.localizedDescription }
        }
    }
    private func formatted(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String { return text }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .fragmentsAllowed]), let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: value)
    }
}

struct NativeMarkdown: View {
    let text: String
    var body: some View {
        let parts = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index % 2 == 1 { code(part) } else { prose(part) }
            }
        }
    }
    private func code(_ text: String) -> some View {
        let split = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let language = split.count > 1 ? String(split[0]) : "Code"
        let body = split.count > 1 ? String(split[1]) : text
        return VStack(alignment: .leading, spacing: 0) {
            HStack { Text(language.isEmpty ? "Code" : language); Spacer(); Button("Copy") { UIPasteboard.general.string = body } }.font(.caption).padding(10).background(.white.opacity(0.07))
            ScrollView(.horizontal) { Text(body).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(12) }
        }.background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func prose(_ text: String) -> some View {
        let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^\\s\\)]+)\\)")
        let ns = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        var cursor = 0
        var pieces: [(String, String?)] = []
        for match in matches {
            if match.range.location > cursor { pieces.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), nil)) }
            pieces.append((ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2))))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { pieces.append((ns.substring(from: cursor), nil)) }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                if let source = piece.1 { RemoteAttachment(source: source, name: piece.0.isEmpty ? "Generated image" : piece.0, image: true) }
                else { Text((try? AttributedString(markdown: piece.0, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(piece.0)).textSelection(.enabled).lineSpacing(4) }
            }
        }
    }
}

struct RemoteAttachment: View {
    @EnvironmentObject var store: OceanStore
    let source: String
    let name: String
    let image: Bool
    @State private var data: Data?
    @State private var failed = false
    @State private var preview: PreviewFile?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if image, let data, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 400).clipShape(RoundedRectangle(cornerRadius: 14))
            } else if image, !failed { ProgressView().frame(height: 80) }
            Button { Task { await open() } } label: { Label(loading ? "Downloading…" : name, systemImage: image ? "photo" : "doc") }.disabled(loading)
            if failed { Text("Preview unavailable. Tap to retry downloading.").font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: source) { if image { await fetch() } }
        .sheet(item: $preview) { file in NativeFilePreview(url: file.url) }
    }
    private func fetch() async {
        guard let api = store.api, let url = api.resource(source) else { failed = true; return }
        do { data = try await api.download(url); failed = false } catch { failed = true }
    }
    private func open() async {
        loading = true; defer { loading = false }
        if data == nil { await fetch() }
        guard let data else { store.error = "Could not download this attachment."; return }
        let suffix = store.api?.resource(source)?.pathExtension ?? ""
        let ext = suffix.isEmpty ? (image ? "png" : "bin") : suffix
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        do { try data.write(to: target); preview = PreviewFile(url: target) } catch { store.error = error.localizedDescription }
    }
}

struct NativeFilePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
