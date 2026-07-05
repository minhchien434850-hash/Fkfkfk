import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var calls = CallCoordinator()

    var body: some View {
        Group {
            if !store.isLoggedIn {
                LoginView()
            } else {
                MainTabView()
                    .overlay {
                        // Bảo trì: khoá app người dùng (admin vẫn dùng được)
                        if store.maintenance && !store.isAdmin {
                            MaintenanceOverlay(message: store.maintenanceMessage)
                        }
                    }
                    // Màn giới thiệu gói PRO/Free hiện sau khi đăng nhập
                    .sheet(isPresented: $store.showPlanIntro) { PlanIntroView() }
                    // Cuộc gọi thoại/video giữa bạn bè (đến & đi)
                    .fullScreenCover(item: $calls.active) { call in
                        CallScreen(call: call, api: store.api) { calls.close() }
                    }
                    .onAppear { calls.configure(api: store.api); calls.startPolling() }
                    .onDisappear { calls.stopPolling() }
            }
        }
        .environmentObject(calls)
        .tint(store.accentColor)
        .preferredColorScheme(store.preferredScheme)
        .buttonStyle(PressableButtonStyle())   // hiệu ứng chạm iOS 26 toàn app
    }
}

// §1.3 — Thẻ lời chào toàn cục (admin đặt), hiện cho mọi người dùng khi mở app.
struct WelcomePopupCard: View {
    let title: String
    let text: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 16) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent, .purple, .pink],
                                                    startPoint: .leading, endPoint: .trailing))
                if !title.isEmpty {
                    Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                }
                Text(text)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onClose) {
                    Text("OK").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(LinearGradient(colors: [Theme.accent, .purple],
                                                   startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .padding(30)
        }
    }
}

struct MaintenanceOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Theme.bgNavy.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 60)).foregroundStyle(Theme.gold)
                RainbowText(text: "KENIOS", size: 38)
                Text("Đang nâng cấp phiên bản")
                    .font(.title3.bold()).foregroundStyle(.white)
                Text(message.isEmpty
                     ? "Ứng dụng đang nâng cấp phiên bản. Vui lòng đợi trong giây lát."
                     : message)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                ProgressView().tint(.white)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("defaultLaunchTab") private var defaultLaunchTab = 2
    @State private var didInitTab = false
    @State private var showUpgrade = false
    // §1.3 — Lời chào TOÀN CỤC (admin đặt trên server) hiện cho MỌI người dùng
    @State private var welcomeTitle = ""
    @State private var welcomeText = ""
    @State private var showWelcomePopup = false
    @State private var welcomeChecked = false
    // §1.2 — Thông báo cập nhật phiên bản mới
    @State private var showUpdate = false
    @State private var updateMsg = ""
    @State private var updateLink = ""
    @State private var updateVersion = ""
    // §1.1 — Thông báo phát cho MỌI người (vd: sản phẩm mới) — đọc trong app, không cần APNs
    @AppStorage("lastSeenNotifId") private var lastSeenNotifId = 0
    @State private var showNotif = false
    @State private var notifTitle = ""
    @State private var notifBody = ""
    // Thông báo tin nhắn mới từ bạn bè
    @AppStorage("lastSeenDMId") private var lastSeenDMId = 0

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    // Số build (tăng dần mỗi lần CI build) — dùng để tự phát hiện bản mới trên GitHub Release.
    static var appBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }
    // Quy số build (run_number) → phiên bản hiển thị dạng X.Y ĐẸP: phần lẻ chạy 0–9 rồi lên số lớn.
    // VD: …3.8 → 3.9 → 4.0 → 4.1… (không còn kiểu xấu "3.104"). Mỗi build CI = +0.1.
    static func versionFromBuild(_ build: Int) -> String {
        let idx = max(0, build - 884)          // build 913 → 3.9 · build 914 → 4.0
        return "\(1 + idx / 10).\(idx % 10)"
    }

    // Tự dò bản mới trên GitHub Release (repo công khai, không cần khoá).
    // Duyệt danh sách release ĐÃ PHÁT HÀNH, lấy số build cao nhất (tag "build-<số>") có kèm .ipa.
    static func checkGitHubUpdate() async -> (build: Int, ipaURL: String, pageURL: String)? {
        let api = "https://api.github.com/repos/minhchien434850-hash/Fkfkfk/releases?per_page=30"
        guard let url = URL(string: api) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var best: (build: Int, ipaURL: String, pageURL: String)? = nil
        for rel in arr {
            if (rel["draft"] as? Bool) == true { continue }
            guard let tag = rel["tag_name"] as? String, tag.lowercased().hasPrefix("build-"),
                  let n = Int(tag.drop { !$0.isNumber }), n > 0 else { continue }
            if let cur = best, n <= cur.build { continue }
            let page = (rel["html_url"] as? String) ?? "https://github.com/minhchien434850-hash/Fkfkfk/releases"
            var ipa = page
            if let assets = rel["assets"] as? [[String: Any]] {
                for a in assets where (a["name"] as? String)?.lowercased().hasSuffix(".ipa") == true {
                    if let dl = a["browser_download_url"] as? String { ipa = dl; break }
                }
            }
            best = (n, ipa, page)
        }
        return best
    }
    // So sánh phiên bản dạng "3.1.2" — trả true nếu `a` mới hơn `b`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    var body: some View {
        // Chỉ 5 tab chính cho gọn & rõ — các mục khác nằm trong "Khám phá"
        TabView(selection: $store.tab) {
            SocialMediaToolsView()
                .tabItem { Label(store.t("Mạng xã hội", "Social"), systemImage: "network") }
                .tag(2)
            VideoFeedView() // TikTok của riêng app
                .tabItem { Label(store.t("Video", "Video"), systemImage: "play.rectangle.on.rectangle.fill") }
                .tag(14)
            StoreView() // App bán hàng (sản phẩm · key · tải game)
                .tabItem { Label(store.t("Cửa hàng", "Store"), systemImage: "bag.fill") }
                .tag(15)
            FriendsView()
                .tabItem { Label(store.t("Bạn bè", "Friends"), systemImage: "person.2.fill") }
                .tag(4)
            ExploreHubView() // lưới tất cả tính năng còn lại
                .tabItem { Label(store.t("Khám phá", "Explore"), systemImage: "square.grid.2x2.fill") }
                .tag(16)
        }
        .onAppear {
            // Lần mở app đầu: nhảy tới tab mặc định do người dùng chọn (Cài đặt)
            if !didInitTab {
                didInitTab = true
                store.tab = [2, 14, 15, 4, 16].contains(defaultLaunchTab) ? defaultLaunchTab : 2
            } else if ![2, 14, 15, 4, 16].contains(store.tab) {
                store.tab = 2
            }
            // Giọng chào: nếu cấu hình TOÀN CỤC (server) đang tải → chờ .task phát cho MỌI người;
            // trường hợp có cài đặt riêng bật sẵn thì phát luôn (playOnce có khoá chống lặp).
            if store.welcomeEnabled {
                WelcomeVoice.shared.playOnce(
                    text: store.welcomeText,
                    voiceId: store.welcomeVoiceId,
                    rate: store.welcomeRate)
            }
        }
        .onChange(of: store.tab) { t in
            // Báo cho admin biết người dùng đang ở mục nào
            let name = tabName(t)
            Task { try? await store.api.sendActivity(name) }
        }
        .task {
            // Giảm tải khởi động (đã bỏ Chat/AI key) → đỡ "đứng" khi mở app
            await store.loadProviders()
            await store.refreshCredits()
            await store.refreshMe()
            // §1.3 + §1.2 — Lấy config server 1 lần: lời chào toàn cục + kiểm tra phiên bản mới
            if !welcomeChecked {
                welcomeChecked = true
                // ƯU TIÊN 1 — Bản KENIOS ĐÃ KÝ cài OTA 1 chạm (không cần ESign).
                // Chỉ nhận khi đúng là bản KENIOS (cùng bundle id) và số build cao hơn.
                if let ota = try? await store.api.appOTAUpdate(), ota.available,
                   let otaLink = ota.installUrl, !otaLink.isEmpty,
                   (ota.bundleId ?? "") == (Bundle.main.bundleIdentifier ?? "com.kenios.codebox"),
                   (ota.build ?? 0) > Self.appBuild {
                    updateLink = otaLink
                    updateVersion = ota.version ?? Self.versionFromBuild(ota.build ?? 0)
                    updateMsg = store.t("Đã có bản cập nhật mới — bấm để cài trực tiếp (không cần ESign).",
                                        "A new update is available — tap to install directly (no ESign).")
                    showUpdate = true
                }
                if let cfg = try? await store.api.storeConfig() {
                    // §1.2 — Admin đặt phiên bản thủ công (nếu OTA chưa kích hoạt)
                    let latest = (cfg.latestVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let link = (cfg.updateUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !showUpdate, !latest.isEmpty, !link.isEmpty, Self.isNewer(latest, than: Self.appVersion) {
                        updateLink = link
                        updateMsg = (cfg.updateMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        updateVersion = latest
                        showUpdate = true
                    }
                    // TỰ ĐỘNG: nếu chưa có nguồn nào → tự dò bản mới trên GitHub Release (bản chưa ký, qua ESign).
                    if !showUpdate, let up = await Self.checkGitHubUpdate(), up.build > Self.appBuild {
                        updateLink = up.ipaURL
                        updateVersion = Self.versionFromBuild(up.build)
                        updateMsg = ""
                        showUpdate = true
                    }
                    // §1.3 — Lời chào toàn cục cho MỌI người
                    if cfg.welcomePopupEnabled == true {
                        let t = (cfg.welcomePopupText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty {
                            welcomeTitle = (cfg.welcomePopupTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            welcomeText = t
                            // Ưu tiên popup cập nhật trước; lời chào hiện nếu không có cập nhật.
                            if !showUpdate { withAnimation(.spring(response: 0.4)) { showWelcomePopup = true } }
                        }
                    }
                    // GIỌNG chào TOÀN CỤC — phát cho MỌI người dùng khi mở app.
                    // Mặc định server bật (welcome_voice_enabled=1); chỉ tắt khi admin đặt = false.
                    if cfg.welcomeVoiceEnabled != false {
                        let vt = (cfg.welcomeVoiceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        // GIỌNG đồng bộ: admin đổi giọng → mọi người nghe giọng đó;
                        // chưa đặt thì mặc định "chị Google" (online).
                        let gvid = (cfg.welcomeVoiceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        WelcomeVoice.shared.playOnce(
                            text: vt.isEmpty ? store.welcomeText : vt,
                            voiceId: gvid.isEmpty ? store.welcomeVoiceId : gvid,
                            rate: cfg.welcomeVoiceRate ?? store.welcomeRate)
                    }
                }
            }
            // §1.1 — Kiểm tra thông báo phát (sản phẩm mới…) ngay khi mở app
            await checkNotifications()
            await checkNewMessages()   // tin nhắn mới từ bạn bè
            // Theo dõi bảo trì + gói theo chu kỳ
            try? await store.api.sendActivity(tabName(store.tab))
            // Đồng bộ bảo trì + gói với máy chủ VPS mỗi 10 giây
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await store.refreshMe()
                await checkNotifications()   // §1.1 — có sản phẩm mới thì hiện ngay (kể cả khi đang mở app)
                await checkNewMessages()     // tin nhắn mới từ bạn bè → hiện thông báo text
            }
        }
        .onChange(of: scenePhase) { phase in
            // Mở lại app từ nền → kiểm tra bảo trì ngay
            if phase == .active { Task { await store.refreshMe() } }
        }
        // Thông báo khi gói PRO vừa hết hạn (tự chuyển về Free)
        .alert(store.t("Gói PRO đã hết hạn", "PRO plan expired"),
               isPresented: $store.planExpiredNotice) {
            Button(store.t("Gia hạn", "Renew")) { showUpgrade = true }
            Button(store.t("Đóng", "Close"), role: .cancel) {}
        } message: {
            Text(store.t("Gói PRO của bạn đã hết hạn và được chuyển về Free. Gia hạn để tiếp tục dùng các tính năng PRO.",
                         "Your PRO plan has expired and was switched to Free. Renew to keep using PRO features."))
        }
        .sheet(isPresented: $showUpgrade) { PaymentView().environmentObject(store) }
        // §1.3 — Popup lời chào toàn cục cho mọi người dùng
        .overlay {
            if showWelcomePopup {
                WelcomePopupCard(title: welcomeTitle, text: welcomeText) {
                    withAnimation(.easeInOut) { showWelcomePopup = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        // §1.1 — Popup thông báo phát (sản phẩm mới…) cho MỌI người dùng
        .overlay {
            if showNotif {
                WelcomePopupCard(title: notifTitle.isEmpty ? store.t("Thông báo", "Notice") : notifTitle,
                                 text: notifBody) {
                    withAnimation(.easeInOut) { showNotif = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        // §1.2 — Thông báo có phiên bản mới, bấm để mở link tải/cập nhật
        .alert(store.t("Có phiên bản mới \(updateVersion)", "New version \(updateVersion) available"),
               isPresented: $showUpdate) {
            Button(store.t("Cập nhật ngay", "Update now")) {
                if let url = URL(string: updateLink) { UIApplication.shared.open(url) }
            }
            Button(store.t("Để sau", "Later"), role: .cancel) {
                // Sau khi tắt cập nhật, mới hiện lời chào (nếu có)
                if !welcomeText.isEmpty { withAnimation(.spring(response: 0.4)) { showWelcomePopup = true } }
            }
        } message: {
            Text(updateMsg.isEmpty
                 ? store.t("Đã có phiên bản mới hơn. Cập nhật để dùng tính năng mới nhất.",
                           "A newer version is available. Update for the latest features.")
                 : updateMsg)
        }
    }

    // §1.1 — Lấy thông báo phát mới nhất; nếu mới hơn lần đã xem → hiện popup cho MỌI người.
    private func checkNotifications() async {
        guard let notifs = try? await store.api.getNotifications(limit: 5),
              let latest = notifs.first else { return }
        guard latest.id > lastSeenNotifId else { return }
        let firstRun = (lastSeenNotifId == 0)
        lastSeenNotifId = latest.id
        // Lần đầu cài / cài lại app: CHỈ ghi mốc, KHÔNG báo lại thông báo cũ.
        // Chỉ báo khi admin thêm sản phẩm MỚI sau mốc này (id lớn hơn ở lần kiểm tra sau).
        if firstRun { return }
        // Hiện BANNER hệ thống (kèm ẢNH sản phẩm nếu có) cho MỌI người dùng — kể cả khi thu nhỏ app.
        store.postProductNotification(body: latest.body.isEmpty ? latest.title : latest.body,
                                      imageURL: latest.image)
        // + popup ngay trong app khi đang mở.
        notifTitle = latest.title
        notifBody = latest.body
        if !showUpdate && !showWelcomePopup {
            withAnimation(.spring(response: 0.4)) { showNotif = true }
        }
        // + ĐỌC TO thông báo bằng GIỌNG ĐỒNG BỘ toàn cục (giọng admin chọn / chị Google).
        if let cfg = try? await store.api.storeConfig(), cfg.notifVoiceEnabled != false {
            let gvid = (cfg.welcomeVoiceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let spoken = latest.title.isEmpty ? latest.body : "\(latest.title). \(latest.body)"
            if !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                WelcomeVoice.shared.announce(
                    text: spoken,
                    voiceId: gvid.isEmpty ? store.welcomeVoiceId : gvid,
                    rate: cfg.welcomeVoiceRate ?? store.welcomeRate)
            }
        }
    }

    // Thông báo tin nhắn mới từ bạn bè (chỉ tin CHƯA đọc → không báo lại tin đã xem trong chat).
    private func checkNewMessages() async {
        guard let msgs = try? await store.api.recentIncomingMessages(afterId: lastSeenDMId),
              !msgs.isEmpty else { return }
        let maxId = msgs.map(\.id).max() ?? lastSeenDMId
        let firstRun = (lastSeenDMId == 0)
        lastSeenDMId = maxId
        if firstRun { return }   // lần đầu chỉ ghi mốc, tránh bung tất cả tin cũ
        let fresh = msgs.filter { ($0.isRead ?? 0) == 0 }.sorted { $0.id < $1.id }
        guard !fresh.isEmpty else { return }
        if fresh.count > 3 {
            store.postLocalNotification(title: "💬 Tin nhắn mới",
                                        body: "Bạn có \(fresh.count) tin nhắn mới từ bạn bè.")
        } else {
            for m in fresh {
                let who = (m.senderName?.isEmpty == false) ? m.senderName! : "Bạn bè"
                store.postLocalNotification(title: "💬 \(who)", body: dmPreview(m.content))
            }
        }
    }

    // Rút gọn nội dung để hiện trong thông báo (tin media → nhãn thân thiện).
    private func dmPreview(_ content: String) -> String {
        if let media = ChatMedia.parse(content) {
            switch media.kind {
            case "img":   return "📷 Đã gửi một ảnh"
            case "video": return "🎥 Đã gửi một video"
            case "audio": return "🎤 Đã gửi tin nhắn thoại"
            default:      return "📎 Đã gửi một tệp"
            }
        }
        return content
    }

    private func tabName(_ t: Int) -> String {
        switch t {
        case 2: return "Mạng xã hội"
        case 3: return "Thư viện"
        case 4: return "Bạn bè"
        case 7: return "Đọc (TTS)"
        case 8: return "Giải trí"
        case 11: return "Công cụ"
        case 12: return "Trò chơi"
        case 13: return "GitHub"
        case 14: return "Video"
        case 15: return "Cửa hàng"
        case 16: return "Khám phá"
        case 5: return "Cài đặt"
        case 6: return "Quản trị"
        default: return "Khác"
        }
    }
}
