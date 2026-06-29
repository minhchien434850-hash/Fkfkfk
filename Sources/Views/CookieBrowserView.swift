import SwiftUI
import WebKit

// MARK: - Cookie Browser View (WKWebView Sheet)
struct CookieBrowserView: View {
    let urlString: String
    let onExtract: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var currentURL = ""
    @State private var autoExtracted = false

    var body: some View {
        NavigationStack {
            CookieWebView(urlString: urlString, loading: $loading, currentURL: $currentURL,
                          onAutoDetect: { cookies in
                guard !autoExtracted else { return }
                autoExtracted = true
                onExtract(cookies)
            })
            .navigationTitle("Đăng nhập tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trích xuất Cookie") {
                        Task {
                            let cookies = await CookieExtractor.extractAll()
                            onExtract(cookies)
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
            .overlay {
                if loading { ProgressView() }
            }
            .overlay(alignment: .bottom) {
                if autoExtracted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Đã tự động lấy cookie sau khi đăng nhập")
                            .font(.caption.bold())
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Cookie Extractor
enum CookieExtractor {
    static func extractAll() async -> String {
        let store = WKWebsiteDataStore.default().httpCookieStore
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                store.getAllCookies { cookies in
                    let cookieArray = cookies.map { cookie -> [String: Any] in
                        [
                            "name": cookie.name,
                            "value": cookie.value,
                            "domain": cookie.domain,
                            "path": cookie.path
                        ]
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: cookieArray, options: .prettyPrinted),
                       let jsonStr = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: jsonStr)
                    } else {
                        let netscape = cookies.map { c -> String in
                            let exp = Int(c.expiresDate?.timeIntervalSince1970 ?? 0)
                            return "\(c.domain)\tTRUE\t\(c.path)\t\(c.isSecure ? "TRUE" : "FALSE")\t\(exp)\t\(c.name)\t\(c.value)"
                        }
                        continuation.resume(returning: netscape.joined(separator: "\n"))
                    }
                }
            }
        }
    }

    static func extractForDomain(_ domain: String) async -> String {
        let store = WKWebsiteDataStore.default().httpCookieStore
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                store.getAllCookies { cookies in
                    let filtered = cookies.filter { $0.domain.contains(domain) }
                    let arr = filtered.map { c -> [String: Any] in
                        ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path]
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted),
                       let json = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: json)
                    } else {
                        continuation.resume(returning: "")
                    }
                }
            }
        }
    }
}

// MARK: - WKWebView with auto-detect login
struct CookieWebView: UIViewRepresentable {
    let urlString: String
    @Binding var loading: Bool
    @Binding var currentURL: String
    var onAutoDetect: ((String) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CookieWebView
        private var loginDetected = false

        init(_ parent: CookieWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.currentURL = webView.url?.absoluteString ?? ""
            checkLoginState(webView: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        private func checkLoginState(webView: WKWebView) {
            guard !loginDetected else { return }
            let url = webView.url?.absoluteString ?? ""

            let isTikTokLoggedIn = url.contains("tiktok.com") &&
                (url.contains("/foryou") || url.contains("/@") || url.contains("/following"))
            let isFacebookLoggedIn = url.contains("facebook.com") &&
                !url.contains("/login") && (url.contains("/home") || url.contains("/?sk=") || url.contains("/feed"))
            let isYouTubeLoggedIn = url.contains("youtube.com") &&
                !url.contains("/signin") && url.contains("/feed")

            if isTikTokLoggedIn || isFacebookLoggedIn || isYouTubeLoggedIn {
                loginDetected = true
                Task { @MainActor in
                    let cookies = await CookieExtractor.extractAll()
                    self.parent.onAutoDetect?(cookies)
                }
            }
        }
    }
}
