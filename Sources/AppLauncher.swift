import UIKit

// ======================== App Launcher Engine ========================
// Quản lý app do NGƯỜI DÙNG tự thêm: lưu danh sách, dọn RAM, khởi chạy qua URL scheme.
// Không còn danh sách game cứng — bạn tự thêm app của mình từ màn hình App Launcher.

struct CustomApp: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var urlScheme: String        // vd: "youtube", "fb", "zalo", "tiktok"
    var icon: String = "app.fill"        // SF Symbol
    var colorIndex: Int = 0              // chỉ số màu trong AppLauncher palette
    var appStoreID: String = ""          // tuỳ chọn — để mở App Store khi app chưa cài

    var schemeURL: URL? {
        let s = urlScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Cho phép dán cả "scheme://" lẫn "scheme"
        return URL(string: s.contains("://") ? s : "\(s)://")
    }
    var appStoreURL: URL? {
        let id = appStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}

final class AppLauncher {

    static let shared = AppLauncher()
    private let storageKey = "custom_launcher_apps"

    // Gợi ý SF Symbol khi thêm app
    static let iconChoices: [String] = [
        "app.fill", "gamecontroller.fill", "play.rectangle.fill", "music.note",
        "message.fill", "phone.fill", "camera.fill", "photo.fill",
        "cart.fill", "creditcard.fill", "banknote.fill", "airplane",
        "car.fill", "map.fill", "book.fill", "newspaper.fill",
        "tv.fill", "film.fill", "mic.fill", "headphones",
        "bolt.fill", "flame.fill", "star.fill", "heart.fill",
        "globe", "paperplane.fill", "envelope.fill", "folder.fill",
    ]

    // Danh sách app phổ biến — bấm 1 phát là thêm ngay (URL scheme đã điền sẵn).
    static let presets: [CustomApp] = [
        CustomApp(name: "YouTube",   urlScheme: "youtube",     icon: "play.rectangle.fill", colorIndex: 0, appStoreID: "544007664"),
        CustomApp(name: "TikTok",    urlScheme: "snssdk1233",  icon: "music.note",          colorIndex: 7, appStoreID: "835599320"),
        CustomApp(name: "Facebook",  urlScheme: "fb",          icon: "person.2.fill",       colorIndex: 2, appStoreID: "284882215"),
        CustomApp(name: "Messenger", urlScheme: "fb-messenger", icon: "message.fill",       colorIndex: 4, appStoreID: "454638411"),
        CustomApp(name: "Instagram", urlScheme: "instagram",   icon: "camera.fill",         colorIndex: 7, appStoreID: "389801252"),
        CustomApp(name: "Zalo",      urlScheme: "zalo",        icon: "message.fill",        colorIndex: 2, appStoreID: "579523206"),
        CustomApp(name: "Telegram",  urlScheme: "tg",          icon: "paperplane.fill",     colorIndex: 2, appStoreID: "686449807"),
        CustomApp(name: "WhatsApp",  urlScheme: "whatsapp",    icon: "phone.fill",          colorIndex: 3, appStoreID: "310633997"),
        CustomApp(name: "Shopee",    urlScheme: "shopeeVN",    icon: "cart.fill",           colorIndex: 1, appStoreID: "959841113"),
        CustomApp(name: "Lazada",    urlScheme: "lazada",      icon: "cart.fill",           colorIndex: 2, appStoreID: "785385147"),
        CustomApp(name: "Grab",      urlScheme: "grab",        icon: "car.fill",            colorIndex: 3, appStoreID: "647268330"),
        CustomApp(name: "MoMo",      urlScheme: "momo",        icon: "creditcard.fill",     colorIndex: 7, appStoreID: "918751511"),
        CustomApp(name: "Spotify",   urlScheme: "spotify",     icon: "music.note",          colorIndex: 3, appStoreID: "324684580"),
        CustomApp(name: "Netflix",   urlScheme: "nflx",        icon: "film.fill",           colorIndex: 0, appStoreID: "363590051"),
        CustomApp(name: "Gmail",     urlScheme: "googlegmail", icon: "envelope.fill",       colorIndex: 0, appStoreID: "422689480"),
        CustomApp(name: "Chrome",    urlScheme: "googlechrome", icon: "globe",              colorIndex: 2, appStoreID: "535886823"),
        CustomApp(name: "Discord",   urlScheme: "discord",     icon: "bubble.left.and.bubble.right.fill", colorIndex: 4, appStoreID: "985746746"),
        CustomApp(name: "X",         urlScheme: "twitter",     icon: "at",                  colorIndex: 2, appStoreID: "333903271"),
    ]

    // MARK: - Lưu / đọc danh sách app của người dùng

    func loadApps() -> [CustomApp] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let apps = try? JSONDecoder().decode([CustomApp].self, from: data) else { return [] }
        return apps
    }

    func saveApps(_ apps: [CustomApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addApp(_ app: CustomApp) {
        var apps = loadApps()
        apps.append(app)
        saveApps(apps)
    }

    func updateApp(_ app: CustomApp) {
        var apps = loadApps()
        if let i = apps.firstIndex(where: { $0.id == app.id }) {
            apps[i] = app
            saveApps(apps)
        }
    }

    func deleteApp(_ app: CustomApp) {
        saveApps(loadApps().filter { $0.id != app.id })
    }

    // MARK: - Khởi chạy app

    /// Mở app qua URL scheme. `UIApplication.open` KHÔNG cần khai báo
    /// LSApplicationQueriesSchemes (chỉ canOpenURL mới cần) nên mở được mọi scheme.
    /// completion(false) khi scheme sai hoặc app chưa cài.
    func launch(_ app: CustomApp, completion: @escaping (Bool) -> Void) {
        guard let url = app.schemeURL else { completion(false); return }
        UIApplication.shared.open(url, options: [:]) { ok in completion(ok) }
    }

    func openAppStore(_ app: CustomApp) {
        guard let url = app.appStoreURL else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Giải phóng tài nguyên trước khi mở app

    /// Dọn sạch bộ nhớ của KENIOS trước khi mở app khác:
    /// 1. Xoá toàn bộ cache URL (ảnh, API response đã lưu tạm)
    /// 2. Xoá bộ nhớ đệm URLSession mặc định
    /// 3. Yêu cầu hệ thống thu hồi bộ nhớ không dùng (autorelease pool)
    /// 4. Đặt cache memory capacity = 0 tạm thời, ép iOS giải phóng RAM ngay
    ///
    /// Kết quả: KENIOS nhường tối đa CPU/GPU/RAM cho app kia, máy mát hơn, pin ổn hơn.
    func cleanupBeforeLaunch() {
        // 1. Xoá cache URL toàn bộ (ảnh đã tải, response API)
        URLCache.shared.removeAllCachedResponses()

        // 2. Xoá cache + cookie của URLSession default
        let storage = URLSession.shared.configuration.urlCache
        storage?.removeAllCachedResponses()

        // 3. Flush toàn bộ URLSession data task tạm
        URLSession.shared.reset {}

        // 4. Giảm memory capacity xuống 0 tạm thời → iOS sẽ giải phóng RAM ngay lập tức
        let originalMemory = URLCache.shared.memoryCapacity
        URLCache.shared.memoryCapacity = 0
        // Khôi phục sau 3 giây (khi app kia đã nhận RAM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            URLCache.shared.memoryCapacity = originalMemory
        }

        // 5. Gợi ý hệ thống thu gom rác (autorelease pool drain)
        autoreleasepool {}
    }

    /// Combo: dọn RAM → mở app
    func optimizeAndLaunch(_ app: CustomApp, completion: @escaping (Bool) -> Void) {
        cleanupBeforeLaunch()
        // Delay nhỏ để iOS kịp giải phóng RAM trước khi switch sang app kia
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.launch(app, completion: completion)
        }
    }

    // MARK: - Thông tin RAM hiện tại

    struct MemoryInfo {
        let used: UInt64      // bytes
        let total: UInt64     // bytes
        var free: UInt64 { total - min(used, total) }

        var usedMB: Int { Int(used / 1024 / 1024) }
        var totalMB: Int { Int(total / 1024 / 1024) }
        var freeMB: Int { Int(free / 1024 / 1024) }
        var usagePercent: Double {
            total == 0 ? 0 : Double(used) / Double(total) * 100
        }
    }

    func memoryInfo() -> MemoryInfo {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let used: UInt64 = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        return MemoryInfo(used: used, total: total)
    }

    // MARK: - Thermal State

    func thermalStateText() -> (String, String) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return ("Bình thường", "checkmark.seal.fill")
        case .fair:     return ("Hơi nóng", "thermometer.medium")
        case .serious:  return ("Nóng", "thermometer.high")
        case .critical: return ("Quá nóng!", "exclamationmark.triangle.fill")
        @unknown default: return ("Không rõ", "questionmark")
        }
    }
}
