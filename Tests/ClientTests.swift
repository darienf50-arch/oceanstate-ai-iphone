import XCTest
@testable import OceanStateAI

final class ClientTests: XCTestCase {
    func testThreeInlineVideosRemainThreePlayers() {
        let text = (1...3).map { "Clip \($0)\n<video src=\"/oceanstate-clips/job/clip-0\($0).mp4?access=sample\" controls playsinline></video>" }.joined(separator: "\n\n")
        let videos = MediaMarkup.pieces(text).filter { $0.kind == "video" }
        XCTAssertEqual(videos.count, 3)
        XCTAssertEqual(Set(videos.compactMap(\.source)).count, 3)
        XCTAssertEqual(videos[1].source, "/oceanstate-clips/job/clip-02.mp4?access=sample")
    }
    func testMixedMediaAndTextPreserved() {
        let pieces = MediaMarkup.pieces("Before ![photo](/image.png) between <VIDEO src='/clip.mp4?a=1&amp;b=2' controls></VIDEO> after")
        XCTAssertEqual(pieces.filter { $0.source != nil }.count, 2)
        XCTAssertEqual(pieces.first?.text, "Before ")
        XCTAssertEqual(pieces.last?.text, " after")
        XCTAssertEqual(pieces.first { $0.kind == "video" }?.source, "/clip.mp4?a=1&b=2")
    }
    func testSelectedBranchExcludesAlternateReplies() {
        let chat: Object = ["history": ["currentId": "b2", "messages": [
            "u1": ["role": "user", "content": "Hello", "parentId": NSNull()],
            "a1": ["role": "assistant", "content": "First", "parentId": "u1"],
            "b1": ["role": "assistant", "content": "Alternative", "parentId": "u1"],
            "u2": ["role": "user", "content": "Continue", "parentId": "b1"],
            "b2": ["role": "assistant", "content": "Second", "parentId": "u2"]]]]
        XCTAssertEqual(ChatBranch.messages(chat).map(\.id), ["u1", "b1", "u2", "b2"])
    }
    func testHistoryCycleStops() {
        let chat: Object = ["history": ["currentId": "a", "messages": ["a": ["role": "user", "content": "One", "parentId": "b"], "b": ["role": "assistant", "content": "Two", "parentId": "a"]]]]
        XCTAssertEqual(ChatBranch.messages(chat).count, 2)
    }
    func testLegacyMessagesSupported() {
        XCTAssertEqual(ChatBranch.messages(["messages": [["id": "1", "role": "user", "content": "Hello"]]]).first?.text, "Hello")
    }
    func testResponsesOutputBecomesVisibleText() {
        let message = ChatMessage.parse(["id": "1", "role": "assistant", "output": [["type": "function_call", "name": "read_file"], ["type": "message", "content": [["type": "output_text", "text": "Answer"]]]]])
        XCTAssertEqual(message.text, "Answer")
        XCTAssertEqual(message.tools.count, 1)
    }
    func testAddressRejectsCredentialsAndNonHTTPS() {
        for address in ["http://example.com", "https://user:password@example.com", "https://example.com?token=abc", "https://example.com/path", "https://example.com#secret"] {
            XCTAssertNil(ServerAddress.parse(address))
        }
        XCTAssertNotNil(ServerAddress.parse(" https://example.com:8443/ "))
    }
    func testCredentialsNeverAttachedToOtherOrigin() throws {
        let api = OceanAPI(base: URL(string: "https://example.com")!, token: "test-token")
        XCTAssertThrowsError(try api.request("https://other.example/file"))
        XCTAssertEqual(try api.request("/api/models").value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertFalse(ServerAddress.sameOrigin(URL(string: "https://example.com")!, URL(string: "https://example.com:8443")!))
    }
    func testPhotoCreatesMultimodalInput() throws {
        let content = MessagePayload.content(text: "Describe", files: [["type": "image", "url": "https://example.com/photo.png"]]) as? [Object]
        XCTAssertEqual(content?.count, 2)
        XCTAssertEqual((content?.last?["image_url"] as? Object)?["url"] as? String, "https://example.com/photo.png")
        XCTAssertEqual(MessagePayload.content(text: "Plain", files: []) as? String, "Plain")
    }
    func testPrivateUploadedPhotoUsesAuthenticatedRelativeHandle() {
        let path = "/api/v1/files/123/content"
        let content = MessagePayload.content(text: "Describe", files: [["type": "image", "url": path]]) as? [Object]
        XCTAssertEqual((content?.last?["image_url"] as? Object)?["url"] as? String, path)
        let api = OceanAPI(base: URL(string: "https://example.com")!)
        XCTAssertEqual(api.resource(path)?.absoluteString, "https://example.com" + path)
        XCTAssertNil(api.resource("http://example.com/image"))
    }
    func testMediaCredentialsStayOnOwnServer() throws {
        let api = OceanAPI(base: URL(string: "https://example.com")!, token: "test-token")
        XCTAssertEqual(try api.mediaRequest(URL(string: "https://example.com/file")!).value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(try api.mediaRequest(URL(string: "https://cdn.example.com/video.mp4")!).value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try api.mediaRequest(URL(string: "http://example.com/file")!))
    }
}
