import Foundation
import Security
import UniformTypeIdentifiers

enum TokenVault {
    static func key(_ server: URL) -> String { "native:" + server.absoluteString }
    static func read(_ server: URL) -> String? {
        let query: Object = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: "OceanStateAI", kSecAttrAccount as String: key(server),
                             kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String?, server: URL) throws {
        let query: Object = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: "OceanStateAI", kSecAttrAccount as String: key(server)]
        SecItemDelete(query as CFDictionary)
        if let token {
            var entry = query
            entry[kSecValueData as String] = Data(token.utf8)
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else {
                throw APIError(message: "Could not store the login securely on this iPhone.")
            }
        }
    }
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let old = response.url, let new = request.url, ServerAddress.sameOrigin(old, new) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

final class OceanAPI {
    let base: URL
    var token: String?
    private let redirect = RedirectGuard()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: redirect, delegateQueue: nil)
    }()
    init(base: URL, token: String? = nil) { self.base = base; self.token = token }
    func resource(_ text: String) -> URL? {
        guard let url = URL(string: text, relativeTo: base)?.absoluteURL,
              url.scheme == "https" else { return nil }
        return url
    }
    func request(_ path: String, method: String = "GET", body: Object? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL, ServerAddress.sameOrigin(base, url) else {
            throw APIError(message: "Invalid server request.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("OceanStateAI-iOS/2", forHTTPHeaderField: "User-Agent")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }
    func checked(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "No response from your PC.") }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? Object
            let detail = value?["detail"] as? String
            throw APIError(message: http.statusCode == 401 ? "Your login expired. Open Settings and sign in again." : (detail ?? "Server returned HTTP \(http.statusCode)."))
        }
        return data
    }
    func json(_ path: String, method: String = "GET", body: Object? = nil) async throws -> Any {
        let data = try await checked(request(path, method: method, body: body))
        return try JSONSerialization.jsonObject(with: data)
    }
    func object(_ path: String, method: String = "GET", body: Object? = nil) async throws -> Object {
        guard let result = try await json(path, method: method, body: body) as? Object else {
            throw APIError(message: "Unexpected response from your PC.")
        }
        return result
    }
    func upload(_ data: Data, name: String, mime: String, transcription: Bool = false) async throws -> Object {
        let boundary = UUID().uuidString
        let process = (mime.hasPrefix("image/") || mime.hasPrefix("video/")) ? "false" : "true"
        var req = try request(transcription ? "/api/v1/audio/transcriptions" : "/api/v1/files/?process=\(process)&process_in_background=false", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let safeName = name.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); req.httpBody = body
        guard let result = try JSONSerialization.jsonObject(with: await checked(req)) as? Object else {
            throw APIError(message: "The server did not return a file record.")
        }
        return result
    }
    func mediaRequest(_ url: URL) throws -> URLRequest {
        guard url.scheme?.lowercased() == "https" else { throw APIError(message: "Media downloads require HTTPS.") }
        var req = URLRequest(url: url)
        if ServerAddress.sameOrigin(base, url), let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }
    func download(_ url: URL) async throws -> Data {
        try await checked(mediaRequest(url))
    }
    func downloadFile(_ url: URL, name: String) async throws -> URL {
        let (temporary, response) = try await session.download(for: mediaRequest(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "This file could not be downloaded. Check the connection and your login.")
        }
        let namedExtension = (name as NSString).pathExtension
        let mimeExtension = http.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        let ext = !namedExtension.isEmpty ? namedExtension : (!url.pathExtension.isEmpty ? url.pathExtension : (mimeExtension ?? "bin"))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }
    func speech(_ text: String) async throws -> Data {
        try await checked(request("/api/v1/audio/speech", method: "POST", body: ["input": text]))
    }
}
