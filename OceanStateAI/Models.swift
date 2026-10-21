import Foundation

typealias Object = [String: Any]

struct ServerModel: Identifiable {
    let id: String
    let name: String
}
struct ServerTool: Identifiable {
    let id: String
    let name: String
    let detail: String
}
struct ChatSummary: Identifiable {
    let id: String
    let title: String
}
struct ProjectSummary: Identifiable {
    let id: String
    let name: String
}
struct Attachment: Identifiable {
    let id: String
    let name: String
    let mime: String
    let remote: Object
    var isImage: Bool { mime.hasPrefix("image/") }
}
struct ChatMessage: Identifiable {
    let id: String
    let role: String
    let text: String
    let raw: Object
    var output: [Object] { raw["output"] as? [Object] ?? [] }
    var done: Bool { raw["done"] as? Bool ?? true }
    var files: [Object] { raw["files"] as? [Object] ?? [] }
    var error: String? {
        guard let value = raw["error"], !(value is NSNull) else { return nil }
        return (value as? String) ?? (value as? Object)?["content"] as? String ?? "The server reported an error."
    }
    var tools: [Object] { output.filter { ($0["type"] as? String) == "function_call" } }
    static func parse(_ raw: Object) -> ChatMessage {
        var text = raw["content"] as? String ?? ""
        if text.isEmpty {
            text = (raw["output"] as? [Object] ?? []).filter { ($0["type"] as? String) == "message" }
                .flatMap { $0["content"] as? [Object] ?? [] }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ChatMessage(id: raw["id"] as? String ?? UUID().uuidString,
                           role: raw["role"] as? String ?? "assistant", text: text, raw: raw)
    }
}

enum ChatBranch {
    // Follow currentId and parentId; sorting all messages mixes alternate answers into the conversation.
    static func messages(_ chat: Object) -> [ChatMessage] {
        let history = chat["history"] as? Object ?? [:]
        if let map = history["messages"] as? [String: Object], !map.isEmpty {
            var current = history["currentId"] as? String
            var seen = Set<String>()
            var result: [ChatMessage] = []
            while let id = current, seen.insert(id).inserted, var raw = map[id] {
                raw["id"] = id
                result.append(.parse(raw))
                current = raw["parentId"] as? String
            }
            return result.reversed()
        }
        return (chat["messages"] as? [Object] ?? []).map(ChatMessage.parse)
    }
}

enum MessagePayload {
    static func content(text: String, files: [Object]) -> Any {
        let images = files.filter { ($0["type"] as? String) == "image" }.compactMap { $0["url"] as? String }
        guard !images.isEmpty else { return text }
        return [["type": "text", "text": text] as Object] + images.map { ["type": "image_url", "image_url": ["url": $0]] as Object }
    }
}

enum ServerAddress {
    static func parse(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return nil }
        parts.path = ""
        return parts.url
    }
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? 443) == (b.port ?? 443)
    }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
