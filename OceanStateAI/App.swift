import SwiftUI
import WebKit

@main
struct OceanStateApp: App {
    var body: some Scene { WindowGroup { OceanStateView() } }
}

struct OceanStateView: View {
    @AppStorage("serverURL") private var server = ""
    @State private var editing = false
    @State private var draft = ""
    @State private var generation = UUID()

    private var validURL: URL? { Self.validate(server) }
    static func validate(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ocean State AI").font(.headline)
                Spacer()
                Button { generation = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reconnect")
                Button { draft = server; editing = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Server settings")
            }.padding().background(.bar)
            if let url = validURL {
                WebPanel(url: url).id(generation)
            } else {
                ContentUnavailableView {
                    Label("Your Ocean State AI", systemImage: "water.waves")
                } description: {
                    Text("Connect to your existing WebUI with its HTTPS address. Your AI continues running on your server.")
                } actions: {
                    Button("Connect server") { draft = server; editing = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    Section("WebUI address") {
                        TextField("https://your-ocean-state-server", text: $draft)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("Use an HTTPS address reachable from your iPhone. Sign in through your normal WebUI login. Do not put passwords or API keys in this address.").font(.footnote)
                    }
                    Button("Save and connect") {
                        server = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        generation = UUID(); editing = false
                    }.disabled(Self.validate(draft) == nil)
                }
                .navigationTitle("Connection")
                .toolbar { Button("Cancel") { editing = false } }
            }
        }
    }
}

struct WebPanel: UIViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if url.scheme == "https" { webView.load(navigationAction.request) }
            }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            showError(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            showError(webView)
        }
        private func showError(_ webView: WKWebView) {
            webView.loadHTMLString("""
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body style="font:18px -apple-system;padding:28px"><h2>Cannot connect</h2>
            <p>Check that your Ocean State AI server is running and reachable from this iPhone.
            If you use a private network, connect to it first.</p>
            <p>Use the reconnect button to retry, or update the address in Settings.</p></body></html>
            """, baseURL: nil)
        }
    }
}
