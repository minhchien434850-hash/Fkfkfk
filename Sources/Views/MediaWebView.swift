import SwiftUI
import WebKit
import AVFoundation

// ======================== Persistent WKWebView delegate (lives with BrowserModel) ========================
private final class WVDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?
    init(_ m: BrowserModel) { model = m; super.init() }

    // Block native-app schemes (youtube://, tiktok://...) but allow http/https/about/blob
    func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let scheme = action.request.url?.scheme?.lowercased(),
           scheme != "http", scheme != "https", scheme != "about", scheme != "blob", scheme != "data" {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Handle target="_blank" / window.open() — load in same webview instead of new window
    func webView(_ wv: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { wv.load(URLRequest(url: url)) }
        return nil
    }

    private func sync(_ wv: WKWebView) {
        guard let m = model else { return }
        m.canGoBack    = wv.canGoBack
        m.canGoForward = wv.canGoForward
        m.isLoading    = wv.isLoading
        m.pageTitle    = wv.title ?? ""
        if let u = wv.url?.absoluteString, u != "about:blank" { m.urlText = u }
    }

    func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) { model?.isLoading = true;  sync(wv) }
    func webView(_ wv: WKWebView, didFinish _: WKNavigation!)               { model?.isLoading = false; sync(wv) }
    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error)           { model?.isLoading = false; sync(wv) }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { model?.isLoading = false; sync(wv) }
}

// ======================== BrowserModel — owns the persistent WKWebView ========================
final class BrowserModel: ObservableObject {
    @Published var urlText     = ""
    @Published var canGoBack   = false
    @Published var canGoForward = false
    @Published var isLoading   = false
    @Published var pageTitle   = ""

    /// Single WKWebView that lives for the entire app session — survives sheet dismiss
    let webView: WKWebView
    private var wvDelegate: WVDelegate!   // strong ref so delegate lives with model

    static let homeURL = "https://www.youtube.com"

    init() {
        // ── Configuration ──
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()   // shared cookies → stay logged in
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []     // auto-play allowed
        cfg.allowsPictureInPictureMediaPlayback = true

        // Override Page Visibility so YouTube/Spotify don't pause when view is hidden
        cfg.userContentController.addUserScript(WKUserScript(
            source: """
            (function(){
              Object.defineProperty(document,'hidden',{get:()=>false,configurable:true});
              Object.defineProperty(document,'visibilityState',{get:()=>'visible',configurable:true});
              document.addEventListener('visibilitychange',function(e){
                e.stopImmediatePropagation();
              },true);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        // ── Create WKWebView ──
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        // Desktop-class Safari UA — YouTube serves full web player (no "open in app" redirect)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = wv
        self.urlText = BrowserModel.homeURL

        // All stored properties assigned — can now use `self`
        let del = WVDelegate(self)
        wv.navigationDelegate = del
        wv.uiDelegate = del
        self.wvDelegate = del

        // Background audio session so video/music continues while switching tabs
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                          options: [.mixWithOthers, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)

        // Load home page on first launch
        loadRaw(BrowserModel.homeURL)
    }

    // MARK: - Public commands

    func go()             { navigate(urlText) }
    func back()           { webView.goBack() }
    func forward()        { webView.goForward() }
    func reload()         { webView.reload() }
    func stopLoading()    { webView.stopLoading() }

    func open(_ raw: String) { urlText = raw; navigate(raw) }

    func navigate(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        // Bare word / phrase → Google search
        if s.contains(" ") || (!s.contains(".") && !s.hasPrefix("http")) {
            let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
            s = "https://www.google.com/search?q=\(q)"
        } else if !s.lowercased().hasPrefix("http") {
            s = "https://" + s
        }
        loadRaw(s)
    }

    private func loadRaw(_ s: String) {
        guard let u = URL(string: s) else { return }
        webView.load(URLRequest(url: u))
    }
}

// ======================== UIViewRepresentable — wraps the persistent WKWebView ========================
struct BrowserWebView: UIViewRepresentable {
    let model: BrowserModel

    func makeUIView(context: Context) -> WKWebView {
        // Return the SAME WKWebView every time — survives sheet dismiss/reopen
        model.webView
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}
}

// ======================== Shortcut tiles ========================
struct WebShortcut: Identifiable, Codable {
    var id   = UUID()
    var name: String
    var url:  String
}

// ======================== Main entertainment browser view ========================
struct MediaWebView: View {
    @ObservedObject var model: BrowserModel
    @FocusState private var addressFocused: Bool

    @AppStorage("kenios_web_shortcuts") private var shortcutsRaw = "[]"
    @State private var showAddShortcut = false
    @State private var newName = ""
    @State private var newURL  = ""

    private let builtinShortcuts: [(String, String, String)] = [
        ("YouTube",   "play.tv.fill",            "https://www.youtube.com"),
        ("Âm nhạc",   "music.note",              "https://soundcloud.com/discover"),
        ("Spotify",   "music.note.list",          "https://open.spotify.com"),
        ("Phim",      "film.fill",               "https://www.youtube.com/results?search_query=phim+hay"),
        ("Tìm kiếm",  "magnifyingglass",          "https://www.google.com"),
    ]

    private var customShortcuts: [WebShortcut] {
        (try? JSONDecoder().decode([WebShortcut].self, from: Data(shortcutsRaw.utf8))) ?? []
    }
    private func saveCustom(_ list: [WebShortcut]) {
        if let d = try? JSONEncoder().encode(list) { shortcutsRaw = String(data: d, encoding: .utf8) ?? "[]" }
    }
    private func addCustom() {
        var url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty ? url : newName
        var list = customShortcuts
        list.append(WebShortcut(name: name, url: url))
        saveCustom(list)
        newName = ""; newURL = ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                // ── Address bar + nav controls ──
                HStack(spacing: 8) {
                    Button { model.back() }    label: { Image(systemName: "chevron.left")  }.disabled(!model.canGoBack)
                    Button { model.forward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canGoForward)

                    HStack(spacing: 6) {
                        Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath" : "globe")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Nhập URL hoặc từ khoá...", text: $model.urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.webSearch)
                            .focused($addressFocused)
                            .submitLabel(.go)
                            .onSubmit { model.go(); addressFocused = false }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())

                    Button {
                        model.isLoading ? model.stopLoading() : model.reload()
                    } label: {
                        Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    }
                }
                .padding(.horizontal)

                // ── Quick shortcuts ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(builtinShortcuts, id: \.0) { s in
                            Button { model.open(s.2); addressFocused = false } label: {
                                Label(s.0, systemImage: s.1)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.accent.opacity(0.14))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                        ForEach(customShortcuts) { s in
                            Button { model.open(s.url); addressFocused = false } label: {
                                Label(s.name, systemImage: "star.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.accent.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    saveCustom(customShortcuts.filter { $0.id != s.id })
                                } label: { Label("Xoá", systemImage: "trash") }
                            }
                        }
                        Button { newName = ""; newURL = ""; showAddShortcut = true } label: {
                            Label("Thêm", systemImage: "plus")
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                if model.isLoading { ProgressView().frame(maxWidth: .infinity) }

                // ── Web content (persistent — keeps playing when sheet is closed) ──
                BrowserWebView(model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Giải trí")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Thêm game / app (web)", isPresented: $showAddShortcut) {
                TextField("Tên (vd: Game của tôi)", text: $newName)
                TextField("Link (vd: crazygames.com)", text: $newURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Thêm") { addCustom() }
                Button("Huỷ", role: .cancel) { }
            } message: {
                Text("Dán link game/website để thêm vào lối tắt. Video YouTube tiếp tục phát khi bạn thoát màn hình này.")
            }
        }
    }
}
