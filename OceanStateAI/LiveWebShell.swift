import SwiftUI
import WebKit
import Network
import CryptoKit

// A transport for this application only. It never changes system VPN settings.
final class HostTrust: NSObject, URLSessionDelegate {
    static let pins = [
        "192.168.1.153": "81A3711EE991CE228FB696A66B916865607EEAA9146EA64DB9722A1EFA51A65E",
        "q3fqhm3ye5dmja4qtzw77lmbta2ne6ygbfs3k44osrwemqdvcxaw5dyd.onion": "D650D072B6B33F22C21B14FE8EBCAA525ED2DF55DB88CC6F26E1F99990E2A358"
    ]
    static func credential(_ challenge: URLAuthenticationChallenge) -> URLCredential? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let expected = pins[challenge.protectionSpace.host],
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02X", $0) }.joined()
        guard digest == expected else { return nil }
        return URLCredential(trust: trust)
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let value = Self.credential(challenge) { completionHandler(.useCredential, value) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

@MainActor final class LiveConnection: ObservableObject {
    @Published var origin: URL?
    @Published var status = "Connecting to your Ocean State host…"
    @Published var failed = false
    var useTor = false
    private var tor: TorThread?
    private let trust = HostTrust()
    static let onion = URL(string: "https://q3fqhm3ye5dmja4qtzw77lmbta2ne6ygbfs3k44osrwemqdvcxaw5dyd.onion")!
    let proxy: [AnyHashable: Any] = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 19062, "SOCKSVersion": "5"]
    func probe(_ url: URL, tunnel: Bool, timeout: Double) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        if tunnel { config.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: 19062))] }
        let session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(from: url.appendingPathComponent("api/config"))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { NSLog("OceanState connection probe (%@): %@", tunnel ? "tunnel" : "LAN", error.localizedDescription); return false }
    }
    func connect() async {
        guard origin == nil else { return }
        failed = false
        let lan = URL(string: "https://192.168.1.153:3243")!
        status = "Looking for your host on this network…"
        if await probe(lan, tunnel: false, timeout: 10) {
            useTor = false; origin = lan; status = "Connected directly • AI on 4090 host"; return
        }
        status = "Starting private tunnel… First connection can take a few minutes."
        if tor == nil {
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OceanStateTunnel", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
                var dir = directory; try dir.setResourceValues(excluded)
                let config = TorConfiguration()
                config.ignoreMissingTorrc = true
                config.dataDirectory = directory
                config.clientOnly = true
                config.avoidDiskWrites = true
                config.options = ["SocksPort": "127.0.0.1:19062", "SafeSocks": "1", "ClientUseIPv6": "1"]
                tor = TorThread(configuration: config); tor?.start()
            } catch { status = "Could not start the tunnel: \(error.localizedDescription)"; failed = true; return }
        }
        for _ in 0..<24 {
            if Task.isCancelled { return }
            if await probe(Self.onion, tunnel: true, timeout: 10) {
                useTor = true; origin = Self.onion; status = "Private tunnel • AI on 4090 host"; return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        status = "Host unavailable. Keep the host PC online, or try another network if Tor is blocked."
        failed = true
    }
}

struct LiveWebRoot: View {
    @StateObject private var connection = LiveConnection()
    @State private var shareLesson = false
    @State private var themes = false
    @AppStorage("oceanstate.mobile.theme") private var themeName = MobileTheme.ocean.rawValue
    private var theme: MobileTheme { MobileTheme(rawValue: themeName) ?? .ocean }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Ocean State AI").font(.headline)
                    Text(connection.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { themes = true } label: { Image(systemName: "paintpalette") }.accessibilityLabel("Choose theme")
                if connection.origin != nil { Button("Share lesson") { shareLesson = true }.font(.caption) }
            }.padding(12)
            if let origin = connection.origin {
                ZStack {
                    HostWebView(origin: origin, tunnel: connection.useTor, theme: theme)
                    ThemeAnimation(theme: theme)
                }
            } else {
                Spacer()
                if !connection.failed { ProgressView().padding() }
                Text(connection.status).multilineTextAlignment(.center).padding()
                if connection.failed { Button("Retry") { Task { await connection.connect() } }.buttonStyle(.borderedProminent) }
                Spacer()
            }
        }
        .background(theme.background).tint(theme.accent).preferredColorScheme(.dark)
        .task { await connection.connect() }
        .sheet(isPresented: $shareLesson) { MobileLessonView(connection: connection) }
        .sheet(isPresented: $themes) { MobileThemePicker() }
    }
}

struct HostWebView: UIViewRepresentable {
    let origin: URL
    let tunnel: Bool
    let theme: MobileTheme
    func makeCoordinator() -> Coordinator { Coordinator(origin: origin, theme: theme) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent per-app storage keeps sign-in; it never imports PC cookies.
        config.websiteDataStore = .default()
        if tunnel {
            config.websiteDataStore.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: 19062))]
        } else { config.websiteDataStore.proxyConfigurations = [] }
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isInspectable = false
        view.load(URLRequest(url: origin))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.theme = theme
        context.coordinator.applyTheme(uiView)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let origin: URL
        var theme: MobileTheme
        init(origin: URL, theme: MobileTheme) { self.origin = origin; self.theme = theme }
        func applyTheme(_ webView: WKWebView) {
            guard let bytes = try? JSONSerialization.data(withJSONObject: [theme.css]), let json = String(data: bytes, encoding: .utf8) else { return }
            webView.evaluateJavaScript("(()=>{let s=document.getElementById('oceanstate-mobile-theme');if(!s){s=document.createElement('style');s.id='oceanstate-mobile-theme';document.head.append(s)}s.textContent=\(json)[0]})()", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyTheme(webView) }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let credential = HostTrust.credential(challenge) { completionHandler(.useCredential, credential) }
            else { completionHandler(.performDefaultHandling, nil) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if ServerAddress.sameOrigin(origin, url) || url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if action.navigationType == .linkActivated, url.scheme == "https" { UIApplication.shared.open(url) }
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ServerAddress.sameOrigin(origin, url) { webView.load(action.request) }
            return nil
        }
    }
}

struct MobileLessonView: View {
    @ObservedObject var connection: LiveConnection
    @Environment(\.dismiss) var dismiss
    @State private var problem = ""
    @State private var solution = ""
    @State private var result = ""
    @State private var sending = false
    var body: some View {
        NavigationStack {
            Form {
                Text("Share a useful fix with your AI. Only the text you submit is retained on the host, labeled as user-confirmed knowledge. No automatic screen, keyboard or other-app collection.")
                TextField("Problem (omit personal information)", text: $problem, axis: .vertical)
                TextField("What worked, and how you checked it", text: $solution, axis: .vertical)
                Text("Do not include passwords, tokens, private files or personal details.").font(.caption)
                Button(sending ? "Sharing…" : "Share this lesson") { Task { await submit() } }
                    .disabled(sending || problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || solution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !result.isEmpty { Text(result) }
            }.navigationTitle("Optional learning")
                .toolbar { Button("Done") { dismiss() } }
        }
    }
    func submit() async {
        guard let origin = connection.origin else { return }
        sending = true; defer { sending = false }
        let config = URLSessionConfiguration.ephemeral
        if connection.useTor { config.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: 19062))] }
        let trust = HostTrust()
        let session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Read only the login belonging to this exact WebUI origin.
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        guard let login = cookies.first(where: { $0.name == "token" && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host }) else {
            result = "Sign in to Ocean State first, then share your lesson."; return
        }
        do {
            var request = URLRequest(url: origin.appendingPathComponent("remote/file-mobile-lesson"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(login.value)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["problem": String(problem.prefix(1000)), "solution": String(solution.prefix(2500)), "consent": true])
            let (_, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { result = "Could not save. Check your sign-in and connection."; return }
            problem = ""; solution = ""; result = "Lesson shared. It is reference knowledge, not a permission or a model weight update."
        } catch { result = error.localizedDescription }
    }
}
