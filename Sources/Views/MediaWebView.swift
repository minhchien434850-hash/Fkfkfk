import SwiftUI
import WebKit
import AVFoundation

// ======================== Ad-block content rules (YouTube + common ad networks) ========================
private let kAdBlockRules = """
[
  {"trigger":{"url-filter":"googlesyndication\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"doubleclick\\\\.net"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"googleadservices\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adservice\\\\.google\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"advertising\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adnxs\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adsystem\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"moatads\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"scorecardresearch\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"amazon-adsystem\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"cdn\\\\.ima\\\\.googlevideo\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"ads\\\\.youtube\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"static\\\\.doubleclick\\\\.net"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"pagead2\\\\.googlesyndication\\\\.com"},"action":{"type":"block"}}
]
"""

// JS injected into every YouTube page — auto-skip ads + hide ad UI
private let kYouTubeAdSkipJS = """
(function(){
  // ── Override Page Visibility so YouTube never pauses ──
  Object.defineProperty(document,'hidden',{get:()=>false,configurable:true});
  Object.defineProperty(document,'visibilityState',{get:()=>'visible',configurable:true});
  document.addEventListener('visibilitychange',function(e){e.stopImmediatePropagation();},true);

  // ── Skip / remove ads ──
  function skipAds(){
    // Click "Skip Ad" / "Skip Ads" buttons when available
    var skip = document.querySelector(
      '.ytp-skip-ad-button, .ytp-ad-skip-button, ' +
      '.ytp-ad-skip-button-modern, button[class*="skip"]'
    );
    if(skip){ skip.click(); }

    // If pre-roll ad is playing → jump to end (forces skip)
    var vid = document.querySelector('video');
    var adBadge = document.querySelector('.ad-showing, .ytp-ad-player-overlay');
    if(vid && adBadge && isFinite(vid.duration) && vid.duration > 0){
      vid.currentTime = vid.duration;
      vid.playbackRate = 16;
    }

    // Hide ad overlay banners & survey modals
    var selectors = [
      '.ytp-ad-overlay-container','.ytp-ad-text-overlay',
      '.ytp-ad-image-overlay','.ytd-action-companion-ad-renderer',
      '.ytd-banner-promo-renderer','ytd-ad-slot-renderer',
      '#masthead-ad','.ytd-display-ad-renderer',
      '.ytp-suggested-action','.ytp-ce-element'
    ];
    selectors.forEach(function(s){
      document.querySelectorAll(s).forEach(function(el){ el.style.display='none'; });
    });
  }

  // Run every 500 ms
  setInterval(skipAds, 500);

  // Also run on DOM mutations (faster reaction)
  var obs = new MutationObserver(skipAds);
  obs.observe(document.documentElement,{childList:true,subtree:true});
})();
"""

// CSS to hide remaining ad UI chrome
private let kYouTubeAdCSS = """
.ytp-ad-overlay-container,
.ytp-ad-text-overlay,
.ytp-ad-image-overlay,
.ytp-ad-preview-container,
#masthead-ad,
ytd-ad-slot-renderer,
.ytd-banner-promo-renderer,
.ytd-display-ad-renderer,
ytd-action-companion-ad-renderer,
.ytp-suggested-action { display:none!important; }
"""

private let kCSSInjectJS = """
(function(){
  var s=document.createElement('style');
  s.textContent=`\(kYouTubeAdCSS)`;
  (document.head||document.documentElement).appendChild(s);
})();
"""

// ======================== WKWebView delegate ========================
private final class WVDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?
    init(_ m: BrowserModel) { model = m; super.init() }

    func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let scheme = action.request.url?.scheme?.lowercased(),
           scheme != "http", scheme != "https", scheme != "about", scheme != "blob", scheme != "data" {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Handle target="_blank" — load in same webview
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

    func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!)               { model?.isLoading = true;  sync(wv) }
    func webView(_ wv: WKWebView, didFinish _: WKNavigation!)                                   { model?.isLoading = false; sync(wv) }
    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error)                 { model?.isLoading = false; sync(wv) }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { model?.isLoading = false; sync(wv) }
}

// ======================== BrowserModel — owns the persistent WKWebView ========================
@MainActor
final class BrowserModel: ObservableObject {
    @Published var urlText      = ""
    @Published var canGoBack    = false
    @Published var canGoForward = false
    @Published var isLoading    = false
    @Published var pageTitle    = ""

    /// Persistent WKWebView — survives sheet dismiss, keeps playing audio in background
    let webView: WKWebView
    private var wvDelegate: WVDelegate!

    static let homeURL = "https://www.youtube.com"

    init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = true

        let uc = cfg.userContentController
        // Visibility bypass + ad-skip JS (runs on every page load)
        uc.addUserScript(WKUserScript(
            source: kYouTubeAdSkipJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        // CSS ad-hider (injected after DOM is ready)
        uc.addUserScript(WKUserScript(
            source: kCSSInjectJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        // Desktop Safari UA → YouTube serves full web player, no native-app redirect
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = wv
        self.urlText = BrowserModel.homeURL

        let del = WVDelegate(self)
        wv.navigationDelegate = del
        wv.uiDelegate = del
        self.wvDelegate = del

        // Background audio: keeps playing when screen locks / user switches apps
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback,
            options: [.mixWithOthers, .allowBluetooth, .allowAirPlay]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        // Compile ad-block content rules on main actor (avoids @MainActor isolation issues)
        Task { [weak self] in
            guard let self else { return }
            if let list = try? await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "kenios-yt-adblock",
                                        encodedContentRuleList: kAdBlockRules) {
                self.webView.configuration.userContentController.add(list)
            }
        }

        loadRaw(BrowserModel.homeURL)
    }

    // MARK: - Commands

    func go()          { navigate(urlText) }
    func back()        { webView.goBack() }
    func forward()     { webView.goForward() }
    func reload()      { webView.reload() }
    func stopLoading() { webView.stopLoading() }
    func open(_ raw: String) { urlText = raw; navigate(raw) }

    func navigate(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
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
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ wv: WKWebView, context: Context) {}
}

// ======================== Shortcut tiles ========================
struct WebShortcut: Identifiable, Codable {
    var id   = UUID()
    var name: String
    var url:  String
}

// ======================== Main entertainment browser ========================
struct MediaWebView: View {
    @ObservedObject var model: BrowserModel
    @FocusState private var addressFocused: Bool

    @AppStorage("kenios_web_shortcuts") private var shortcutsRaw = "[]"
    @State private var showAddShortcut = false
    @State private var newName = ""
    @State private var newURL  = ""

    private let builtinShortcuts: [(String, String, String)] = [
        ("YouTube",   "play.tv.fill",         "https://www.youtube.com"),
        ("Âm nhạc",  "music.note",            "https://soundcloud.com/discover"),
        ("Spotify",   "music.note.list",       "https://open.spotify.com"),
        ("Phim",      "film.fill",             "https://www.youtube.com/results?search_query=phim+hay"),
        ("Tìm kiếm",  "magnifyingglass",       "https://www.google.com"),
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
        var list = customShortcuts; list.append(WebShortcut(name: name, url: url))
        saveCustom(list); newName = ""; newURL = ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                // ── Address bar ──
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

                    Button { model.isLoading ? model.stopLoading() : model.reload() } label: {
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

                // ── Web view (persistent — survives sheet close, keeps audio) ──
                BrowserWebView(model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Giải trí")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Thêm game / app (web)", isPresented: $showAddShortcut) {
                TextField("Tên (vd: Game của tôi)", text: $newName)
                TextField("Link (vd: crazygames.com)", text: $newURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Thêm") { addCustom() }
                Button("Huỷ", role: .cancel) { }
            } message: {
                Text("Video YouTube tiếp tục phát khi bạn thoát màn hình này hoặc khoá màn hình.")
            }
        }
    }
}
