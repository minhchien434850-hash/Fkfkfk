import Foundation
import SwiftUI
import UIKit
import UserNotifications

// Bảng màu accent người dùng có thể chọn
let kAccentColors: [(name: String, color: Color)] = [
    ("blue",   Color(red: 0.0,  green: 0.58, blue: 0.96)),
    ("purple", Color(red: 0.65, green: 0.45, blue: 0.95)),
    ("pink",   Color(red: 0.96, green: 0.22, blue: 0.60)),
    ("orange", Color(red: 0.98, green: 0.50, blue: 0.05)),
    ("green",  Color(red: 0.20, green: 0.78, blue: 0.35)),
    ("teal",   Color(red: 0.00, green: 0.80, blue: 0.78)),
    ("red",    Color(red: 0.95, green: 0.18, blue: 0.18)),
    ("gold",   Color(red: 1.00, green: 0.84, blue: 0.00)),
    ("indigo", Color(red: 0.35, green: 0.34, blue: 0.84)),
]

@MainActor
final class AppStore: ObservableObject {
    @Published var baseURL: String
    @Published var serverType: String
    @Published var token: String?
    @Published var username: String?
    @Published var email: String?
    @Published var phone: String?
    @Published var isAdmin: Bool = false
    @Published var plan: String = "free"
    @Published var credits: Int = 0
    @Published var planExpires: Int = 0          // unix giây; 0 = không hạn / vĩnh viễn
    @Published var planExpiredNotice = false     // gói vừa hết hạn → hiện thông báo 1 lần
    @Published var publicId: String = ""
    @Published var userId: Int?

    // §6.1 — ID hiển thị: bỏ tiền tố "KEN" ở đầu (kể cả khi máy chủ chưa cập nhật).
    var displayPublicId: String {
        let p = publicId
        if p.uppercased().hasPrefix("KEN") { return String(p.dropFirst(3)) }
        return p
    }

    // Bảo trì (admin bật → khoá app người dùng)
    @Published var maintenance: Bool = false
    @Published var maintenanceMessage: String = ""

    /// Admin luôn Pro vĩnh viễn; còn lại tuỳ gói.
    var isPro: Bool { isAdmin || plan.lowercased() == "pro" }

    /// Ngày hết hạn gói (dd/MM/yyyy) hoặc nil nếu vĩnh viễn / không có hạn.
    var planExpiryText: String? {
        guard !isAdmin, planExpires > 0 else { return nil }
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(planExpires)))
    }

    @Published var providers: [Provider] = []
    @Published var configuredKeys: Set<String> = []
    @Published var conversations: [Conversation] = []

    @Published var tab: Int = 0
    @Published var activeConversation: Conversation?

    @Published var isDark: Bool
    /// Chế độ giao diện: "system" (tự động/cân bằng) · "light" (sáng) · "dark" (tối)
    @Published var themeMode: String
    @Published var language: String
    @Published var systemPrompt: String
    @Published var showPlanIntro: Bool = false   // hiện màn giới thiệu gói PRO/Free sau đăng nhập

    // Màu accent người dùng chọn (tên: "blue", "purple", ...)
    @Published var accentColorName: String
    // Logo có hiệu ứng động hay không
    @Published var logoAnimated: Bool

    // Lời chào khi mở app (TTS)
    @Published var welcomeEnabled: Bool
    @Published var welcomeText: String
    @Published var welcomeVoiceId: String   // AVSpeechSynthesisVoice.identifier hoặc "" = mặc định
    @Published var welcomeRate: Float       // 0.3 (chậm) … 0.65 (nhanh); mặc định 0.5

    @Published var profiles: [ServerProfile] = []

    @Published var biometricsEnabled: Bool
    @Published var favorites: [FavoriteMessage] = []
    @Published var promptTemplates: [PromptTemplate] = []

    @Published var friends: [FriendItem] = []
    @Published var friendRequests: [FriendRequestItem] = []
    @Published var directMessages: [Int: [DirectMessageItem]] = [:]

    private let d = UserDefaults.standard

    /// Màu accent hiện tại của app (phụ thuộc vào accentColorName)
    var accentColor: Color {
        kAccentColors.first(where: { $0.name == accentColorName })?.color
            ?? Color(red: 0.0, green: 0.58, blue: 0.96)
    }

    init() {
        var savedURL = d.string(forKey: "baseURL") ?? ""
        // Nâng cấp máy chủ cũ (IP HTTP) → domain HTTPS mới cho khách hàng đang dùng app,
        // để không ai phải nhập lại máy chủ. Chỉ đổi đúng địa chỉ IP cũ đã biết.
        let legacyHosts = ["http://103.131.56.11", "https://103.131.56.11",
                           "http://103.131.56.11/", "https://103.131.56.11/"]
        if legacyHosts.contains(savedURL) {
            savedURL = Config.defaultServerURL
            d.set(savedURL, forKey: "baseURL")
        }
        baseURL = savedURL.isEmpty ? Config.defaultServerURL : savedURL
        serverType = d.string(forKey: "serverType") ?? Config.defaultServerType
        username = d.string(forKey: "username")
        email = d.string(forKey: "email")
        phone = d.string(forKey: "phone")
        // Cài app mới: Keychain trên iOS KHÔNG tự xoá khi gỡ app → token cũ còn sót
        // làm app "tự vào thẳng". UserDefaults bị xoá khi gỡ app, nên dùng cờ này
        // để phát hiện lần cài mới và xoá token cũ → luôn bắt đầu ở màn đăng nhập.
        if !d.bool(forKey: "kenios_installed_flag") {
            Keychain.delete("token")
            d.set(true, forKey: "kenios_installed_flag")
        }
        token = Keychain.load("token")
        isAdmin = d.bool(forKey: "isAdmin")
        plan = d.string(forKey: "plan") ?? "free"
        credits = d.integer(forKey: "credits")
        publicId = d.string(forKey: "publicId") ?? ""
        let uid = d.integer(forKey: "userId")
        userId = uid > 0 ? uid : nil
        isDark = d.object(forKey: "isDark") as? Bool ?? true
        themeMode = d.string(forKey: "themeMode") ?? ((d.object(forKey: "isDark") as? Bool ?? true) ? "dark" : "light")
        language = d.string(forKey: "language") ?? "vi"
        systemPrompt = d.string(forKey: "systemPrompt") ?? ""
        biometricsEnabled = d.bool(forKey: "biometricsEnabled")
        accentColorName = d.string(forKey: "accentColorName") ?? "blue"
        logoAnimated = d.bool(forKey: "logoAnimated")
        welcomeEnabled = d.bool(forKey: "welcomeEnabled")
        welcomeText = d.string(forKey: "welcomeText") ?? "Chào mừng bạn đã đến với KENIOS. Chúc bạn một ngày tốt lành!"
        welcomeVoiceId = d.string(forKey: "welcomeVoiceId") ?? ""
        welcomeRate = d.object(forKey: "welcomeRate") as? Float ?? 0.5
        if let data = d.data(forKey: "profiles"),
           let list = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = list
        }
    }

    var api: APIClient { APIClient(baseURL: baseURL, token: token) }
    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespaces).isEmpty }
    var isLoggedIn: Bool { token != nil }

    func setDark(_ v: Bool) { isDark = v; d.set(v, forKey: "isDark") }
    /// Đổi chế độ giao diện. mode ∈ {"system","light","dark"}
    func setThemeMode(_ mode: String) {
        themeMode = mode
        d.set(mode, forKey: "themeMode")
        if mode == "light" { isDark = false; d.set(false, forKey: "isDark") }
        else if mode == "dark" { isDark = true; d.set(true, forKey: "isDark") }
    }
    /// ColorScheme áp cho toàn app: nil = theo hệ thống (cân bằng).
    var preferredScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    func setLanguage(_ v: String) {
        language = v; d.set(v, forKey: "language")
        objectWillChange.send()   // ép toàn app vẽ lại ngay khi đổi ngôn ngữ
    }

    /// Dịch sang ngôn ngữ hiện tại.
    /// vi = chuỗi tiếng Việt, en = chuỗi tiếng Anh (cũng là khoá tra cứu bảng dịch).
    func t(_ vi: String, _ en: String) -> String {
        switch language {
        case "vi": return vi
        case "en": return en
        default:   return L10n.translate(en, to: language) ?? en
        }
    }

    // ===== Nhớ tài khoản & mật khẩu (lưu trong Keychain, có mã hoá) =====
    var rememberLogin: Bool {
        get { d.bool(forKey: "rememberLogin") }
        set { d.set(newValue, forKey: "rememberLogin") }
    }
    var savedUsername: String { Keychain.load("saved_username") ?? "" }
    var savedPassword: String { Keychain.load("saved_password") ?? "" }

    func saveCredentials(_ u: String, _ p: String) {
        Keychain.save("saved_username", u)
        Keychain.save("saved_password", p)
        rememberLogin = true
    }
    func forgetCredentials() {
        Keychain.delete("saved_username")
        Keychain.delete("saved_password")
        rememberLogin = false
    }
    func setSystemPrompt(_ v: String) { systemPrompt = v; d.set(v, forKey: "systemPrompt") }
    func setBiometrics(_ v: Bool) { biometricsEnabled = v; d.set(v, forKey: "biometricsEnabled") }

    func setAccentColor(_ name: String) { accentColorName = name; d.set(name, forKey: "accentColorName") }
    func setLogoAnimated(_ v: Bool) { logoAnimated = v; d.set(v, forKey: "logoAnimated") }
    func setWelcomeEnabled(_ v: Bool) { welcomeEnabled = v; d.set(v, forKey: "welcomeEnabled") }
    func setWelcomeText(_ v: String) { welcomeText = v; d.set(v, forKey: "welcomeText") }
    func setWelcomeVoiceId(_ v: String) { welcomeVoiceId = v; d.set(v, forKey: "welcomeVoiceId") }
    func setWelcomeRate(_ v: Float) { welcomeRate = v; d.set(v, forKey: "welcomeRate") }

    /// Xin quyền thông báo từ iOS (không force, người dùng chủ động bấm)
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Gửi local notification thông thường
    func postLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Thông báo sản phẩm mới — hiện banner (kèm ẢNH sản phẩm nếu có) + đọc giọng khi app đang mở
    func postProductNotification(title: String = "🛒 KENIOS Cửa hàng", body: String, imageURL: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = NotifSoundFile.sound   // chuông tuỳ chỉnh — kêu cả khi tắt app
        content.categoryIdentifier = "KENIOS_PRODUCT"

        func submit(_ attachments: [UNNotificationAttachment]) {
            content.attachments = attachments
            let req = UNNotificationRequest(identifier: "prod-\(UUID().uuidString)",
                                            content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }

        // Có ảnh → tải về tệp tạm rồi đính kèm (rich notification có hình như kênh cửa hàng).
        if let s = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
           let url = URL(string: s) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("notif_\(UUID().uuidString).\(ext)")
                    try data.write(to: tmp)
                    let att = try UNNotificationAttachment(identifier: "img", url: tmp, options: nil)
                    await MainActor.run { submit([att]) }
                } catch {
                    await MainActor.run { submit([]) }   // lỗi tải ảnh → vẫn hiện thông báo chữ
                }
            }
        } else {
            submit([])
        }
    }

    /// Thông báo bảo trì — hiện banner + đọc giọng nói khi app đang mở
    func postMaintenanceNotification(message: String) {
        let body = message.isEmpty
            ? "Ứng dụng KENIOS đang được nâng cấp phiên bản. Vui lòng chờ trong giây lát."
            : message
        let content = UNMutableNotificationContent()
        content.title = "🔧 KENIOS - Thông báo bảo trì"
        content.body = body
        content.sound = NotifSoundFile.sound   // chuông tuỳ chỉnh — kêu cả khi tắt app
        content.categoryIdentifier = "KENIOS_MAINTENANCE"
        let req = UNNotificationRequest(identifier: "maint-\(UUID().uuidString)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func saveServer(url: String, type: String) {
        baseURL = url; serverType = type
        d.set(url, forKey: "baseURL"); d.set(type, forKey: "serverType")
    }

    // --- Hồ sơ kết nối (mỗi khách có VPS/hosting riêng) ---
    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { d.set(data, forKey: "profiles") }
    }
    func addProfile(name: String, type: String, url: String) {
        let p = ServerProfile(name: name, type: type, url: url)
        profiles.append(p); persistProfiles()
        selectProfile(p)
    }
    func selectProfile(_ p: ServerProfile) { saveServer(url: p.url, type: p.type) }
    func deleteProfile(_ p: ServerProfile) {
        profiles.removeAll { $0.id == p.id }; persistProfiles()
    }

    /// Định danh thiết bị (để trial 7 ngày chỉ 1 lần/máy). Ổn định trên cùng 1 máy/cùng nhà cung cấp.
    var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? ""
    }

    func setAuth(_ resp: AuthResponse) {
        token = resp.token; username = resp.user.username
        email = resp.user.email; phone = resp.user.phone
        isAdmin = resp.user.isAdmin ?? false
        plan = resp.user.plan ?? "free"
        credits = resp.user.credits ?? 0
        publicId = resp.user.publicId ?? ""
        userId = resp.user.id
        Keychain.save("token", resp.token)
        d.set(resp.user.username, forKey: "username")
        d.set(resp.user.email ?? "", forKey: "email")
        d.set(resp.user.phone ?? "", forKey: "phone")
        d.set(isAdmin, forKey: "isAdmin")
        d.set(plan, forKey: "plan")
        d.set(credits, forKey: "credits")
        d.set(publicId, forKey: "publicId")
        d.set(resp.user.id, forKey: "userId")
        showPlanIntro = true   // hiện màn giới thiệu gói PRO/Free sau khi đăng nhập
        // Tải âm thanh thông báo DÙNG CHUNG (toàn cục) từ máy chủ
        Task { await loadNotifSounds() }
    }

    /// Tải cấu hình âm thanh thông báo dùng chung từ máy chủ và áp vào máy.
    func loadNotifSounds() async {
        if let json = try? await api.getNotifSounds(), !json.isEmpty {
            applyNotifSounds(json)
        }
    }

    /// Ghi cấu hình âm thanh thông báo (JSON từ máy chủ) vào UserDefaults để TTS dùng.
    func applyNotifSounds(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for ev in ["gift", "follow", "share"] {
            guard let s = obj[ev] as? [String: String] else { continue }
            if let id = s["id"], !id.isEmpty { d.set(id, forKey: "tts_sound_\(ev)") }
            if let url = s["url"] { d.set(url, forKey: "tts_sound_url_\(ev)") }
        }
        // Khôi phục KHO âm tùy chỉnh (không giới hạn)
        if let lib = obj["library"] as? [[String: String]],
           let ld = try? JSONSerialization.data(withJSONObject: lib),
           let ls = String(data: ld, encoding: .utf8) {
            d.set(ls, forKey: "tts_custom_sounds")
        }
    }

    /// Đẩy cấu hình âm thanh thông báo (3 sự kiện + kho tùy chỉnh) lên máy chủ để lưu lâu dài.
    func saveNotifSounds() async {
        var dict: [String: Any] = [:]
        for ev in ["gift", "follow", "share"] {
            dict[ev] = ["id": d.string(forKey: "tts_sound_\(ev)") ?? "",
                        "url": d.string(forKey: "tts_sound_url_\(ev)") ?? ""]
        }
        if let raw = d.string(forKey: "tts_custom_sounds"),
           let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            dict["library"] = arr
        }
        try? await api.saveNotifSounds(dict)
    }

    /// Tải lại hồ sơ + trạng thái bảo trì.
    func refreshMe() async {
        if let me = try? await api.getMe() {
            isAdmin = me.isAdmin ?? false
            plan = me.plan ?? "free"
            planExpires = me.planExpires ?? 0
            if me.planExpired == true { planExpiredNotice = true }
            publicId = me.publicId ?? publicId
            userId = me.id
            d.set(isAdmin, forKey: "isAdmin"); d.set(plan, forKey: "plan")
            d.set(publicId, forKey: "publicId")
            d.set(me.id, forKey: "userId")
        }
        if let st = try? await api.appStatus() {
            let wasOff = !maintenance
            maintenance = st.maintenance
            maintenanceMessage = st.message
            // Đồng bộ vào UserDefaults để background task đọc được
            d.set(st.maintenance, forKey: "bgLastMaintenance")
            // Phát thông báo + giọng khi bảo trì vừa bật (chỉ với người dùng thường)
            if st.maintenance && wasOff && !isAdmin {
                postMaintenanceNotification(message: st.message)
            }
        }
    }

    /// Lưu trạng thái hiện tại vào UserDefaults để background task dùng khi app bị tắt
    func syncStateForBackground() {
        d.set(maintenance, forKey: "bgLastMaintenance")
        // bgLastCatCount được cập nhật từ StoreView sau mỗi lần reload
    }

    func refreshCredits() async {
        if let c = try? await api.myCredits() {
            credits = c.credits; plan = c.plan
            d.set(plan, forKey: "plan"); d.set(credits, forKey: "credits")
        }
    }

    func updateLocalUser(email: String?, phone: String?) {
        if let email { self.email = email; d.set(email, forKey: "email") }
        if let phone { self.phone = phone; d.set(phone, forKey: "phone") }
    }

    /// Bỏ qua tự-đăng-nhập đúng 1 lần ngay sau khi người dùng bấm Đăng xuất
    /// (tránh kẹt: vừa đăng xuất lại tự vào). Lần mở app sau vẫn tự đăng nhập.
    var suppressAutoLogin = false

    func logout() {
        token = nil; username = nil; isAdmin = false; plan = "free"; credits = 0
        Keychain.delete("token")
        providers = []; configuredKeys = []; conversations = []
        activeConversation = nil; tab = 0
        favorites = []; promptTemplates = []
        friends = []; friendRequests = []; directMessages = [:]
        d.set(false, forKey: "isAdmin")
        showPlanIntro = false
        suppressAutoLogin = true   // sau khi đăng xuất chỉ điền sẵn, không tự đăng nhập ngay
    }

    func loadProviders() async {
        if let l = try? await api.getProviders() { providers = l }
        // KENIOS AI tự host: không cần key → luôn coi là đã cấu hình
        if providers.contains(where: { $0.id == "kenios" }) { configuredKeys.insert("kenios") }
    }
    func loadKeys() async {
        if let l = try? await api.listKeys() {
            var s = Set(l.map { $0.provider })
            if providers.contains(where: { $0.id == "kenios" }) { s.insert("kenios") }
            configuredKeys = s
        }
    }
    func refreshConversations() async { if let l = try? await api.conversations() { conversations = l } }
    func openConversation(_ c: Conversation?) { activeConversation = c; tab = 0 }

    func refreshFavorites() async {
        if let l = try? await api.listFavorites() { favorites = l }
    }

    func refreshPrompts() async {
        if let l = try? await api.listPrompts() { promptTemplates = l }
    }

    func refreshFriends() async {
        if let l = try? await api.listFriends() { friends = l }
    }

    func refreshFriendRequests() async {
        if let l = try? await api.listFriendRequests() { friendRequests = l }
    }

    func refreshDirectMessages(friendId: Int) async {
        if let l = try? await api.getDirectMessages(friendId: friendId) {
            directMessages[friendId] = l
        }
    }
}
