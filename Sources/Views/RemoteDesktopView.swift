import SwiftUI
import WebKit

// ============================================================
//  §8 — Điều khiển máy tính từ xa (Remote Desktop)
//
//  App sideload qua eSign KHÔNG thể nhúng client RDP/UltraViewer gốc
//  (FreeRDP/native P2P) — sẽ vượt khả năng & quyền của app.
//  Giải pháp KHẢ THI cho điều khiển PC THẬT: mở cổng remote-desktop nền web
//  (noVNC · Apache Guacamole · RustDesk · Chrome Remote Desktop · Windows App)
//  ngay trong app bằng WKWebView — xem & điều khiển chuột/bàn phím màn hình PC.
// ============================================================

struct RemoteDesktopConn: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var kind: String   // "rdp" (cổng web) | "p2p" (UltraViewer/RustDesk)
}

struct RemoteDesktopView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("remoteDesktopConns") private var connsRaw: String = "[]"
    @State private var showAdd = false
    @State private var openConn: RemoteDesktopConn? = nil

    private var conns: [RemoteDesktopConn] {
        (try? JSONDecoder().decode([RemoteDesktopConn].self, from: Data(connsRaw.utf8))) ?? []
    }
    private func save(_ arr: [RemoteDesktopConn]) {
        if let d = try? JSONEncoder().encode(arr) { connsRaw = String(data: d, encoding: .utf8) ?? "[]" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KHeroHeader(icon: "display",
                                title: store.t("Điều khiển PC từ xa", "Remote PC Control"),
                                subtitle: store.t("Xem & điều khiển màn hình máy tính", "View & control your PC screen"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Danh sách kết nối đã lưu
                Section(store.t("Kết nối đã lưu", "Saved connections")) {
                    if conns.isEmpty {
                        Text(store.t("Chưa có kết nối. Bấm ➕ để thêm cổng điều khiển từ xa.",
                                     "No connections yet. Tap ➕ to add a remote-desktop gateway."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(conns) { c in
                            Button { openConn = c } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: c.kind == "p2p" ? "person.2.wave.2.fill" : "display")
                                        .font(.title3).foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(c.kind == "p2p" ? Color.orange : Theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                        Text(c.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete { idx in var a = conns; a.remove(atOffsets: idx); save(a) }
                    }
                }

                // Hai chế độ theo tài liệu §8
                Section(store.t("Hai chế độ (theo yêu cầu §8)", "Two modes (spec §8)")) {
                    modeRow(icon: "display", color: Theme.accent,
                            title: store.t("Phần 1 · Kiểu RDP (Windows App)", "Part 1 · RDP-like"),
                            desc: store.t("Nhập ID/mật khẩu/IP máy tính qua cổng web RDP (Guacamole / Windows App).",
                                          "Enter PC ID/password/IP via a web RDP gateway (Guacamole / Windows App)."))
                    modeRow(icon: "person.2.wave.2.fill", color: .orange,
                            title: store.t("Phần 2 · Kiểu UltraViewer (P2P)", "Part 2 · UltraViewer-like (P2P)"),
                            desc: store.t("Mã số + mật khẩu ngẫu nhiên, kết nối nhanh điện thoại ↔ máy tính qua RustDesk.",
                                          "Numeric ID + random password, quick phone ↔ PC via RustDesk."))
                }

                // Trường hợp THUÊ PC qua web (nhà cung cấp cloud PC/máy game)
                Section(store.t("Thuê PC qua web (đăng nhập nhà cung cấp)", "Rented cloud PC (provider login)")) {
                    Text(store.t("Nếu anh THUÊ máy qua một trang web (phải đăng nhập trang đó mới vào được PC): bấm ➕ ở trên → chọn 'RDP (cổng web)' → dán ĐÚNG LINK trang điều khiển/đăng nhập của nhà cung cấp → Lưu.",
                                 "If you rent a PC via a website (you must log in there to reach the PC): tap ➕ → pick 'RDP (web)' → paste the provider's control/login URL → Save."))
                        .font(.caption)
                    Text(store.t("Mở kết nối → đăng nhập NGAY TRONG APP. App GIỮ đăng nhập: lần sau bấm vào là vào thẳng màn hình PC, khỏi đăng nhập lại (trừ khi anh xoá app).",
                                 "Open it → log in inside the app. Login is remembered: next time you go straight in without logging in again."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Hướng dẫn cài phía máy tính (tự dựng cổng)
                Section(store.t("Hoặc tự dựng cổng điều khiển (cài 1 lần trên máy tính)", "Or set up your own gateway (once)")) {
                    guideRow("1", store.t("RustDesk (khuyên dùng, giống UltraViewer): cài RustDesk trên PC → bật 'Web client' hoặc self-host, dán link vào đây.",
                                          "RustDesk (recommended, like UltraViewer): install on PC → enable Web client / self-host, paste link here."),
                             link: "https://rustdesk.com")
                    guideRow("2", store.t("Apache Guacamole: dựng gateway HTML5 RDP/VNC trên VPS, mở bằng link cổng web.",
                                          "Apache Guacamole: HTML5 RDP/VNC gateway on a VPS, open via web URL."),
                             link: "https://guacamole.apache.org")
                    guideRow("3", store.t("Chrome Remote Desktop: đăng nhập cùng tài khoản Google, dán remotedesktop.google.com.",
                                          "Chrome Remote Desktop: same Google account, paste remotedesktop.google.com."),
                             link: "https://remotedesktop.google.com/access")
                    Text(store.t("Sau khi có link cổng web, bấm ➕ ở trên để lưu và mở điều khiển ngay trong app.",
                                 "Once you have the web gateway URL, tap ➕ above to save and control it right in the app."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("Điều khiển PC từ xa", "Remote PC Control"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.t("Đóng", "Close")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddRemoteDesktopView { new in var a = conns; a.append(new); save(a) }
            }
            .fullScreenCover(item: $openConn) { c in RemoteDesktopSession(conn: c) }
        }
    }

    private func modeRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func guideRow(_ n: String, _ text: String, link: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.accent).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.caption)
                if let u = URL(string: link) {
                    Link(link, destination: u).font(.caption2)
                }
            }
        }
    }
}

// MARK: - Thêm kết nối
struct AddRemoteDesktopView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    var onSave: (RemoteDesktopConn) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var kind = "rdp"

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Tên gợi nhớ", "Display name")) {
                    TextField(store.t("Vd: Máy tính nhà", "e.g. Home PC"), text: $name)
                }
                Section(store.t("Chế độ", "Mode")) {
                    Picker("", selection: $kind) {
                        Text(store.t("RDP (cổng web)", "RDP (web)")).tag("rdp")
                        Text("P2P / RustDesk").tag("p2p")
                    }.pickerStyle(.segmented)
                }
                Section(store.t("Đường dẫn cổng điều khiển (URL)", "Remote-desktop URL")) {
                    TextField("https://...", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text(store.t("Dán link cổng web RDP/VNC (Guacamole, noVNC, RustDesk web, Chrome Remote Desktop...).",
                                 "Paste a web RDP/VNC gateway link (Guacamole, noVNC, RustDesk web, Chrome Remote Desktop...)."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("Thêm kết nối", "Add connection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.t("Huỷ", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Lưu", "Save")) {
                        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !u.isEmpty, !u.hasPrefix("http") { u = "https://" + u }
                        onSave(RemoteDesktopConn(name: name.isEmpty ? u : name, url: u, kind: kind))
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Phiên điều khiển (WKWebView toàn màn hình)
struct RemoteDesktopSession: View {
    let conn: RemoteDesktopConn
    @Environment(\.dismiss) var dismiss
    @State private var loading = true
    @State private var desktopUA = true
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteDesktopWebView(urlString: conn.url, desktopUA: desktopUA,
                                 reloadToken: reloadToken, loading: $loading)
                .ignoresSafeArea(edges: .bottom)

            if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Đang kết nối tới màn hình PC...").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack {
                HStack(spacing: 14) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                    }
                    Text(conn.name).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    // Đổi User-Agent (một số cổng cần bố cục desktop)
                    Button { desktopUA.toggle(); reloadToken += 1 } label: {
                        Image(systemName: desktopUA ? "desktopcomputer" : "iphone")
                            .font(.body).foregroundStyle(.white.opacity(0.9))
                    }
                    Button { reloadToken += 1 } label: {
                        Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                Spacer()
            }
        }
    }
}

// Giữ WKWebView sống theo từng kết nối → ĐĂNG NHẬP 1 LẦN, lần sau vào thẳng
// (cookie + phiên đăng nhập của trang thuê PC không bị mất khi đóng/mở lại).
final class RDWebViews {
    static let shared = RDWebViews()
    private var cache: [String: WKWebView] = [:]

    func view(for key: String, desktopUA: Bool) -> (WKWebView, Bool) {
        if let v = cache[key] { return (v, false) }   // đã có → không cần nạp lại
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = WKWebsiteDataStore.default()   // cookie lưu xuống đĩa
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.scrollView.minimumZoomScale = 1
        wv.scrollView.maximumZoomScale = 6
        wv.isOpaque = false
        wv.backgroundColor = .black
        cache[key] = wv
        return (wv, true)
    }

    func drop(_ key: String) { cache[key] = nil }
}

struct RemoteDesktopWebView: UIViewRepresentable {
    let urlString: String
    let desktopUA: Bool
    let reloadToken: Int
    @Binding var loading: Bool

    private static let desktopAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func makeUIView(context: Context) -> WKWebView {
        let (wv, isNew) = RDWebViews.shared.view(for: urlString, desktopUA: desktopUA)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = desktopUA ? Self.desktopAgent : nil
        if isNew || wv.url == nil {
            context.coordinator.load(wv, urlString)   // chỉ nạp lần đầu; sau đó giữ nguyên phiên
        } else {
            DispatchQueue.main.async { self.loading = false }
        }
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        // Chỉ nạp lại khi người dùng CHỦ ĐỘNG bấm tải lại hoặc đổi User-Agent.
        if context.coordinator.lastToken != reloadToken || context.coordinator.lastUA != desktopUA {
            context.coordinator.lastToken = reloadToken
            context.coordinator.lastUA = desktopUA
            wv.customUserAgent = desktopUA ? Self.desktopAgent : nil
            context.coordinator.load(wv, urlString)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: RemoteDesktopWebView
        var lastToken: Int
        var lastUA: Bool
        init(_ p: RemoteDesktopWebView) { parent = p; lastToken = p.reloadToken; lastUA = p.desktopUA }

        func load(_ wv: WKWebView, _ s: String) {
            guard let url = URL(string: s) else { return }
            DispatchQueue.main.async { self.parent.loading = true }
            wv.load(URLRequest(url: url))
        }
        func webView(_ wv: WKWebView, didFinish n: WKNavigation!) { parent.loading = false }
        func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) { parent.loading = false }
        func webView(_ wv: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { parent.loading = false }
    }
}
