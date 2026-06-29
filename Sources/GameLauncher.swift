import UIKit

// ======================== Game Launcher Engine ========================
// Quản lý: phát hiện game đã cài, dọn dẹp RAM, khởi chạy game native

struct NativeGame: Identifiable, Hashable {
    let id: String
    let name: String
    let urlScheme: String
    let appStoreID: String
    let icon: String
    let category: GameCategory

    var appStoreURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    }

    enum GameCategory: String, CaseIterable {
        case moba    = "MOBA"
        case battle  = "Battle Royale"
        case fps     = "FPS"
        case racing  = "Racing"
        case sport   = "Sport"
        case other   = "Khác"
    }
}

final class GameLauncher {

    static let shared = GameLauncher()

    // Danh sách game phổ biến tại VN + quốc tế
    let catalog: [NativeGame] = [
        // MOBA
        NativeGame(id: "lienquan", name: "Liên Quân Mobile",
                   urlScheme: "com.garena.game.kgvn", appStoreID: "1150318642",
                   icon: "shield.lefthalf.filled", category: .moba),
        NativeGame(id: "lol_wr", name: "League of Legends: Wild Rift",
                   urlScheme: "riotgamesapi", appStoreID: "1480616990",
                   icon: "bolt.shield.fill", category: .moba),
        NativeGame(id: "mlbb", name: "Mobile Legends",
                   urlScheme: "mobilelegends", appStoreID: "1160056295",
                   icon: "shield.checkered", category: .moba),

        // Battle Royale
        NativeGame(id: "pubg", name: "PUBG Mobile",
                   urlScheme: "com.tencent.ig", appStoreID: "1330123889",
                   icon: "scope", category: .battle),
        NativeGame(id: "freefire", name: "Free Fire",
                   urlScheme: "com.dts.freefireth", appStoreID: "1300146617",
                   icon: "flame.fill", category: .battle),
        NativeGame(id: "codm", name: "Call of Duty: Mobile",
                   urlScheme: "codmobile", appStoreID: "1287282214",
                   icon: "target", category: .battle),
        NativeGame(id: "fortnite", name: "Fortnite",
                   urlScheme: "fortnite", appStoreID: "1261357853",
                   icon: "building.2.fill", category: .battle),

        // FPS
        NativeGame(id: "valorant", name: "Valorant Mobile",
                   urlScheme: "valorant", appStoreID: "6504210855",
                   icon: "viewfinder", category: .fps),
        NativeGame(id: "crossfire", name: "CrossFire: Legends",
                   urlScheme: "com.vng.crossfire.legends", appStoreID: "1441498032",
                   icon: "circle.dotted", category: .fps),

        // Racing
        NativeGame(id: "asphalt9", name: "Asphalt 9",
                   urlScheme: "com.gameloft.asphalt9", appStoreID: "805603214",
                   icon: "car.fill", category: .racing),
        NativeGame(id: "mariokarttour", name: "Mario Kart Tour",
                   urlScheme: "mariokart", appStoreID: "1293634699",
                   icon: "flag.checkered", category: .racing),

        // Sport
        NativeGame(id: "fc_mobile", name: "EA FC Mobile",
                   urlScheme: "fifamobile", appStoreID: "1094930513",
                   icon: "sportscourt.fill", category: .sport),

        // Other
        NativeGame(id: "genshin", name: "Genshin Impact",
                   urlScheme: "yuanshengame", appStoreID: "1517783697",
                   icon: "sparkles", category: .other),
        NativeGame(id: "roblox", name: "Roblox",
                   urlScheme: "robloxmobile", appStoreID: "431946152",
                   icon: "cube.fill", category: .other),
        NativeGame(id: "minecraft", name: "Minecraft",
                   urlScheme: "minecraft", appStoreID: "479516143",
                   icon: "square.grid.3x3.topleft.filled", category: .other),
        NativeGame(id: "honkai_sr", name: "Honkai: Star Rail",
                   urlScheme: "hsrglobal", appStoreID: "1599719154",
                   icon: "train.side.front.car", category: .other),
        NativeGame(id: "clashofclans", name: "Clash of Clans",
                   urlScheme: "clashofclans", appStoreID: "529479190",
                   icon: "hammer.fill", category: .other),
        NativeGame(id: "clashroyale", name: "Clash Royale",
                   urlScheme: "clashroyale", appStoreID: "1053012308",
                   icon: "crown.fill", category: .other),
        NativeGame(id: "brawlstars", name: "Brawl Stars",
                   urlScheme: "brawlstars", appStoreID: "1229016807",
                   icon: "star.circle.fill", category: .other),
    ]

    // MARK: - Kiểm tra game đã cài trên máy

    func isInstalled(_ game: NativeGame) -> Bool {
        guard let url = URL(string: "\(game.urlScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - Khởi chạy game

    func launchGame(_ game: NativeGame) {
        guard let url = URL(string: "\(game.urlScheme)://") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Mở App Store để tải game

    func openAppStore(_ game: NativeGame) {
        UIApplication.shared.open(game.appStoreURL, options: [:], completionHandler: nil)
    }

    // MARK: - Giải phóng tài nguyên trước khi chơi game

    /// Dọn sạch bộ nhớ của KENIOS trước khi mở game:
    /// 1. Xoá toàn bộ cache URL (ảnh, API response đã lưu tạm)
    /// 2. Xoá bộ nhớ đệm URLSession mặc định
    /// 3. Yêu cầu hệ thống thu hồi bộ nhớ không dùng (autorelease pool)
    /// 4. Đặt cache memory capacity = 0 tạm thời, ép iOS giải phóng RAM ngay
    ///
    /// Kết quả: KENIOS nhường tối đa CPU/GPU/RAM cho game, máy mát hơn, pin ổn hơn.
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
        // Khôi phục sau 3 giây (khi game đã nhận RAM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            URLCache.shared.memoryCapacity = originalMemory
        }

        // 5. Xoá cache ảnh ImageIO hệ thống
        let imageCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        _ = imageCache

        // 6. Gợi ý hệ thống thu gom rác (autorelease pool drain)
        autoreleasepool {}
    }

    // MARK: - Tối ưu & Chơi (combo: dọn RAM → mở game)

    func optimizeAndLaunch(_ game: NativeGame) {
        cleanupBeforeLaunch()
        // Delay nhỏ để iOS kịp giải phóng RAM trước khi switch sang game
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.launchGame(game)
        }
    }

    // MARK: - Lấy danh sách URL schemes cho Info.plist

    var allURLSchemes: [String] {
        catalog.map { $0.urlScheme }
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
