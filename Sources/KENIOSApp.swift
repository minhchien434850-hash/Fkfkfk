import SwiftUI
import UserNotifications
import BackgroundTasks
import AVFoundation

// ============================ App Delegate — thông báo nền + background refresh ============================
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    static let bgTaskId = "com.kenios.codebox.refresh"

    weak var appStore: AppStore?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Gắn nút "ẩn bàn phím" lên mọi ô nhập trong toàn app
        KeyboardDismissBar.installGlobally()

        // Đặt delegate thông báo
        UNUserNotificationCenter.current().delegate = self

        // Xin quyền thông báo + đăng ký APNs để nhận push thật
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }

        // Đăng ký background task để kiểm tra server khi app bị tắt
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppDelegate.bgTaskId, using: nil
        ) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }

        return true
    }

    // MARK: - APNs device token
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenStr, forKey: "apnsDeviceToken")
        // Gửi token lên server nếu đã đăng nhập
        if let store = appStore, let token = Keychain.load("token"), !token.isEmpty {
            let api = store.api
            Task { _ = try? await api.registerDeviceToken(tokenStr) }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Thiết bị simulator hoặc chưa cấu hình APNs — bỏ qua
    }

    // MARK: - Background refresh

    /// Lên lịch lần kiểm tra tiếp theo (iOS tự quyết định khi nào chạy, thường 15–60 phút)
    static func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // sớm nhất sau 15 phút
        try? BGTaskScheduler.shared.submit(req)
    }

    /// Chạy ngầm: kiểm tra sản phẩm mới & bảo trì, phát thông báo nếu có thay đổi
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Hủy task nếu quá hạn
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        let ud = UserDefaults.standard
        let baseURL = ud.string(forKey: "baseURL") ?? Config.defaultServerURL
        guard !baseURL.isEmpty else { task.setTaskCompleted(success: true); return }
        let token = Keychain.load("token")
        let api = APIClient(baseURL: baseURL, token: token)

        Task {
            var ok = true

            // --- Kiểm tra danh mục sản phẩm mới ---
            if let cats = try? await api.storeCategories() {
                let saved = ud.integer(forKey: "bgLastCatCount")
                let now = cats.count
                if now > saved && saved > 0 {
                    AppDelegate.postBgNotification(
                        title: "🛒 KENIOS Cửa hàng",
                        body: "KENIOS vừa cập nhật \(now - saved) danh mục sản phẩm mới!",
                        category: "KENIOS_PRODUCT")
                }
                ud.set(now, forKey: "bgLastCatCount")
            } else { ok = false }

            // --- Kiểm tra bảo trì ---
            if let st = try? await api.appStatus() {
                let wasOff = !ud.bool(forKey: "bgLastMaintenance")
                ud.set(st.maintenance, forKey: "bgLastMaintenance")
                if st.maintenance && wasOff {
                    let msg = st.message.isEmpty
                        ? "Ứng dụng KENIOS đang được nâng cấp phiên bản. Vui lòng chờ trong giây lát."
                        : st.message
                    AppDelegate.postBgNotification(
                        title: "🔧 KENIOS - Thông báo bảo trì",
                        body: msg,
                        category: "KENIOS_MAINTENANCE")
                }
            } else { ok = false }

            // Lên lịch lần kiểm tra tiếp theo
            AppDelegate.scheduleNextRefresh()
            task.setTaskCompleted(success: ok)
        }
    }

    /// Gửi local notification từ background task
    private static func postBgNotification(title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let req = UNNotificationRequest(identifier: "\(category)-\(UUID().uuidString)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Hiển thị banner + âm thanh ngay cả khi app đang mở ở foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .badge, .sound])

        // Đọc thông báo bằng giọng nói khi app đang chạy (chỉ product/maintenance)
        let cat = notification.request.content.categoryIdentifier
        if cat == "KENIOS_PRODUCT" || cat == "KENIOS_MAINTENANCE" {
            let text = notification.request.content.body
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                WelcomeVoice.shared.testSpeak(text: text, voiceId: "", rate: 0.48)
            }
        }
    }

    /// Xử lý khi người dùng bấm vào thông báo
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        handler()
    }
}

// ============================ App Entry Point ============================
@main
struct KENIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()

    init() {
        // Bộ nhớ đệm ảnh CỰC LỚN → ảnh logo/danh mục/sản phẩm không bao giờ phải tải lại,
        // giữ qua cả các lần mở app. Đĩa đặt 1TB (giới hạn thật là dung lượng máy → coi như
        // không giới hạn); RAM giữ 256MB cho an toàn (RAM quá lớn sẽ làm app tràn bộ nhớ & crash).
        let cache = URLCache(memoryCapacity: 256 * 1024 * 1024,
                             diskCapacity: 1024 * 1024 * 1024 * 1024,  // 1TB
                             diskPath: "kenios_img_cache")
        URLCache.shared = cache

        // ===== Giao diện THÍCH ỨNG sáng/tối (§2.1): tối = navy sâu + chữ trắng;
        // sáng = nền hệ thống + chữ đậm — hết lem màu khi chuyển Light Mode. =====
        // Nền thanh (nav/tab/toolbar): tối→navy, sáng→trắng hệ thống.
        let barBg = UIColor { tc in
            tc.userInterfaceStyle == .dark ? Theme.bgNavyUI : UIColor.systemBackground
        }
        // Nền bảng/list: tối→navy, sáng→nền nhóm hệ thống.
        let tableBg = UIColor { tc in
            tc.userInterfaceStyle == .dark ? Theme.bgNavyUI : UIColor.systemGroupedBackground
        }
        // Nền ô/thẻ: tối→navy thẻ, sáng→nền phụ hệ thống.
        let cardBg = UIColor { tc in
            tc.userInterfaceStyle == .dark ? Theme.cardNavyUI : UIColor.secondarySystemGroupedBackground
        }
        // Chữ tiêu đề: tối→trắng, sáng→đen (label).
        let titleCol = UIColor { tc in
            tc.userInterfaceStyle == .dark ? .white : .label
        }
        let tintCol = UIColor(red: 0.0, green: 0.58, blue: 0.96, alpha: 1)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = barBg
        tab.shadowColor = UIColor.separator
        let selected = tab.stackedLayoutAppearance.selected
        let normal   = tab.stackedLayoutAppearance.normal
        selected.iconColor = tintCol
        selected.titleTextAttributes = [.foregroundColor: tintCol]
        normal.iconColor = UIColor.secondaryLabel
        normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = barBg
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: titleCol]
        nav.largeTitleTextAttributes = [.foregroundColor: titleCol]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        UITableView.appearance().backgroundColor = tableBg
        UITableViewCell.appearance().backgroundColor = cardBg
        UICollectionView.appearance().backgroundColor = tableBg

        let bar = UIToolbarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = barBg
        UIToolbar.appearance().standardAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(store.accentColor)
                .onAppear {
                    // Wire appStore vào delegate để có thể gửi device token khi đăng nhập
                    appDelegate.appStore = store
                    // Nếu đã đăng nhập và có device token, gửi lên server
                    if let savedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken"),
                       !savedToken.isEmpty, let token = Keychain.load("token"), !token.isEmpty {
                        Task { _ = try? await store.api.registerDeviceToken(savedToken) }
                    }
                    // Lên lịch background refresh ngay khi app mở
                    AppDelegate.scheduleNextRefresh()
                    // Đồng bộ trạng thái hiện tại vào UserDefaults cho background task dùng
                    store.syncStateForBackground()
                }
        }
    }
}
