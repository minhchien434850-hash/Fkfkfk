import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

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
            }
        }
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
            // §1.3 — Lấy lời chào toàn cục từ server, hiện popup 1 lần cho MỌI người
            if !welcomeChecked {
                welcomeChecked = true
                if let cfg = try? await store.api.storeConfig(), cfg.welcomePopupEnabled == true {
                    let t = (cfg.welcomePopupText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        welcomeTitle = (cfg.welcomePopupTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        welcomeText = t
                        withAnimation(.spring(response: 0.4)) { showWelcomePopup = true }
                    }
                }
            }
            // Theo dõi bảo trì + gói theo chu kỳ
            try? await store.api.sendActivity(tabName(store.tab))
            // Đồng bộ bảo trì + gói với máy chủ VPS mỗi 10 giây
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await store.refreshMe()
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
