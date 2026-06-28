import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import WebKit
import Photos


// MARK: - Cookie Browser View (WKWebView Sheet)
struct CookieBrowserView: View {
    let urlString: String
    let onExtract: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var loading = true
    
    var body: some View {
        NavigationStack {
            WebViewWrapper(urlString: urlString, loading: $loading)
                .navigationTitle("Đăng nhập tài khoản")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Hủy") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Trích xuất Cookie") {
                            Task {
                                let cookies = await extractCookies()
                                onExtract(cookies)
                                dismiss()
                            }
                        }
                        .bold()
                    }
                }
                .overlay {
                    if loading {
                        ProgressView()
                    }
                }
        }
    }
    
    private func extractCookies() async -> String {
        let store = WKWebsiteDataStore.default().httpCookieStore
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                store.getAllCookies { cookies in
                    // Format cookies as JSON
                    let cookieArray = cookies.map { cookie -> [String: Any] in
                        let dict: [String: Any] = [
                            "name": cookie.name,
                            "value": cookie.value,
                            "domain": cookie.domain,
                            "path": cookie.path
                        ]
                        return dict
                    }
                    
                    if let data = try? JSONSerialization.data(withJSONObject: cookieArray, options: .prettyPrinted),
                       let jsonStr = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: jsonStr)
                    } else {
                        // Fallback to Netscape format
                        let netscapeLines = cookies.map { cookie -> String in
                            let expires = Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
                            return "\(cookie.domain)\tTRUE\t\(cookie.path)\t\(cookie.isSecure ? "TRUE" : "FALSE")\t\(expires)\t\(cookie.name)\t\(cookie.value)"
                        }
                        continuation.resume(returning: netscapeLines.joined(separator: "\n"))
                    }
                }
            }
        }
    }
}

// MARK: - WKWebView UIViewRepresentable
struct WebViewWrapper: UIViewRepresentable {
    let urlString: String
    @Binding var loading: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
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
        var parent: WebViewWrapper
        
        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }
    }
}
