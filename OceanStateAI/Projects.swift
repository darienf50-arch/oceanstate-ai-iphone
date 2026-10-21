import SwiftUI

struct ProjectView: View {
    @EnvironmentObject var store: OceanStore
    let project: ProjectSummary
    let closeHistory: () -> Void
    @State private var chats: [ChatSummary] = []
    @State private var loading = true
    @State private var failed: String?
    var body: some View {
        List {
            Section { Text("Projects group your server conversations. Project instructions and knowledge still need compatibility testing. Coding files on your PC are managed by the PC tools.").font(.footnote).foregroundStyle(.secondary) }
            Button("New project conversation", systemImage: "square.and.pencil") {
                store.newConversation(); store.folderID = project.id; closeHistory()
            }
            if loading { ProgressView() }
            if let failed { Text(failed).foregroundStyle(.orange) }
            ForEach(chats) { chat in
                Button(chat.title) { Task { await store.open(chat.id) }; closeHistory() }
            }
        }.navigationTitle(project.name).task { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let result = try await store.api?.json("/api/v1/chats/folder/\(project.id)/list") as? [Object] ?? []
            chats = result.compactMap { item in guard let id = item["id"] as? String else { return nil }; return ChatSummary(id: id, title: item["title"] as? String ?? "Conversation") }
            failed = nil
        } catch { failed = error.localizedDescription }
    }
}
