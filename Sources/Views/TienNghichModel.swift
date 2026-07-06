import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Dữ liệu lưu
struct TNSave: Codable {
    var created = false
    var name = "Vương Lâm"
    var server = "Thiên Nam"
    var sect = "hamtien"
    var level = 1            // Cấp độ 1–100 (làm nhiệm vụ để lên)
    var levelExp = 0
    var realm = 0
    var stage = 1            // tầng trong cảnh giới (1–9)
    var exp = 0
    var hp = 120
    var linhThach = 0
    var tienNgoc = 0         // 🔮 Tiên Ngọc — nguyên liệu quý để đột phá cảnh giới cao
    var chapter = 0          // cốt truyện đã qua
    var arenaRank = 0        // số cao thủ đã hạ ở Đấu Đài
    var weaponLv = 0         // Luyện Khí — cấp vũ khí (+công)
    var armorLv = 0          // Luyện Khí — cấp giáp (+thủ)
    var danAtk = 0           // Luyện Đan — cộng công vĩnh viễn
    var danHp = 0            // Luyện Đan — cộng máu vĩnh viễn
    var linhThao = 0         // nguyên liệu: linh thảo (luyện đan)
    var khoangThach = 0      // nguyên liệu: khoáng thạch (luyện khí)
    var ownedPets: [String] = []
    var activePet = ""       // thú cưng đang đồng hành
    var guild = ""           // bang hội đang gia nhập
    var guildContrib = 0     // cống hiến bang
    var pvpPoints = 0        // điểm danh vọng PvP
    var pvpWins = 0
    var pvpLosses = 0
    var spouse = ""          // đạo lữ đã kết duyên (id)
    var affinity = 0         // độ thân mật với đạo lữ (tặng quà tăng)
    var ownedMounts: [String] = []
    var activeMount = ""     // thú cưỡi đang cưỡi (thú bay)
    var dailyDate = ""       // ngày (yyyy-MM-dd) của phiên nhiệm vụ hằng ngày hiện tại
    var dailyProg: [String: Int] = [:]   // tiến độ từng nhiệm vụ ngày
    var dailyClaimed: [String] = []      // nhiệm vụ ngày đã lĩnh thưởng
    var dailyStreak = 0      // chuỗi ngày hoàn thành liên tiếp
    var lastStreakDate = ""  // ngày cuối cộng streak (tránh cộng trùng)
    var lastFreeGift = ""    // ngày (yyyy-MM-dd) đã nhận quà miễn phí ở cửa hàng nạp
    var totalRecharged = 0   // tổng linh thạch đã nạp (mốc VIP)
    var lastVipGift = ""     // ngày đã nhận rương đặc quyền VIP
    var ownedWings: [String] = []
    var activeWing = ""      // thời trang cánh đang đeo
    var ownedHalos: [String] = []
    var activeHalo = ""      // hào quang đang khoác
    var claimedAch: [String] = []   // thành tựu đã lĩnh thưởng
    var unlockedTitles: [String] = []  // danh hiệu đã mở khoá
    var activeTitle = ""     // danh hiệu đang dùng
    var totalWins = 0        // tổng số trận thắng (thống kê thành tựu)
    // Túi đồ & trang bị
    var inventory: [TNGearData] = []
    var equipWeapon: TNGearData? = nil
    var equipArmor: TNGearData? = nil
    var equipAccessory: TNGearData? = nil
    // Tâm pháp (id → cấp)
    var techniques: [String: Int] = [:]
    // Điểm danh tích luỹ
    var checkinCount = 0
    var lastCheckin = ""
    // Phụ bản đã vượt (id)
    var clearedDungeons: [String] = []
    var skin = "default"
    var ownedSkins = ["default"]
    var skills = ["kiem"]

    private var tier: Int { realm * 9 + stage }
    private var sectAtk: Double { tnSect(sect).atkMul }
    private var sectDef: Double { tnSect(sect).defMul }
    private var sectHp: Double { tnSect(sect).hpMul }

    var weaponName: String { weaponLv <= 0 ? "Tay không" : "Phi Kiếm +\(weaponLv)" }
    var armorName: String { armorLv <= 0 ? "Vải thô" : "Linh Giáp +\(armorLv)" }
    var levelExpMax: Int { level * 120 }
    var isMaxLevel: Bool { level >= 100 }
    var expMax: Int { 80 + tier * 45 }
    private var petAtkB: Int { tnPet(activePet)?.atk ?? 0 }
    private var petDefB: Int { tnPet(activePet)?.def ?? 0 }
    private var petHpB: Int { tnPet(activePet)?.hp ?? 0 }
    private var guildAtkMul: Double { 1 + (tnGuild(guild)?.atkBuff ?? 0) }
    private var guildHpMul: Double { 1 + (tnGuild(guild)?.hpBuff ?? 0) }
    private var mountAtkB: Int { tnMount(activeMount)?.atk ?? 0 }
    private var mountDefB: Int { tnMount(activeMount)?.def ?? 0 }
    private var mountHpB: Int { tnMount(activeMount)?.hp ?? 0 }
    // Đạo lữ: mỗi bậc thân mật (mỗi 100 điểm) cộng nhẹ công & máu
    var affinityTier: Int { min(affinity / 100, 5) }
    private var spouseAtkB: Int { spouse.isEmpty ? 0 : affinityTier * 12 }
    private var spouseHpB: Int { spouse.isEmpty ? 0 : affinityTier * 60 }
    // VIP: bậc tính theo tổng linh thạch đã nạp (0–6) → đặc quyền cộng chỉ số
    var vip: Int { min(totalRecharged / 5000, 6) }
    private var vipAtkB: Int { vip * 18 }
    private var vipHpB: Int { vip * 100 }
    // Thời trang cánh & hào quang: vừa đẹp vừa cộng nhẹ chỉ số
    private var wingAtkB: Int { tnWing(activeWing)?.atk ?? 0 }
    private var wingHpB: Int { tnWing(activeWing)?.hp ?? 0 }
    private var haloAtkB: Int { tnHalo(activeHalo)?.atk ?? 0 }
    private var haloDefB: Int { tnHalo(activeHalo)?.def ?? 0 }
    // Danh hiệu: đang dùng cộng chỉ số uy danh
    private var titleAtkB: Int { tnTitle(activeTitle)?.atk ?? 0 }
    private var titleHpB: Int { tnTitle(activeTitle)?.hp ?? 0 }
    // Trang bị (túi đồ): tổng chỉ số 3 ô đang mặc
    private var gearAtkB: Int { (equipWeapon?.atk ?? 0) + (equipArmor?.atk ?? 0) + (equipAccessory?.atk ?? 0) }
    private var gearDefB: Int { (equipWeapon?.def ?? 0) + (equipArmor?.def ?? 0) + (equipAccessory?.def ?? 0) }
    private var gearHpB: Int { (equipWeapon?.hp ?? 0) + (equipArmor?.hp ?? 0) + (equipAccessory?.hp ?? 0) }
    // Tâm pháp: cộng % và chỉ số phẳng theo cấp
    var techAtkPct: Double { Double(techniques["satpha"] ?? 0) * 0.03 }
    var techHpPct: Double { Double(techniques["luyenthe"] ?? 0) * 0.025 }
    var techDefB: Int { (techniques["kimcang"] ?? 0) * 7 }
    var hpMax: Int { Int((Double(120 + tier * 70 + level * 22) * sectHp + Double(danHp + petHpB + mountHpB + spouseHpB + vipHpB + wingHpB + titleHpB + gearHpB)) * guildHpMul * (1 + techHpPct)) }
    var mpMax: Int { 60 + tier * 40 + level * 6 }
    var atk: Int { Int((Double(18 + tier * 12 + level * 4) * sectAtk + Double(weaponLv * 15 + danAtk + petAtkB + mountAtkB + spouseAtkB + vipAtkB + wingAtkB + haloAtkB + titleAtkB + gearAtkB)) * guildAtkMul * (1 + techAtkPct)) }
    var def: Int { Int(Double(4 + tier * 4 + level) * sectDef) + armorLv * 8 + petDefB + mountDefB + haloDefB + gearDefB + techDefB }
    var realmEnum: TNRealm { TNRealm(rawValue: min(realm, TNRealm.allCases.count - 1)) ?? .luyenKhi }
    var canBreakthrough: Bool { exp >= expMax }
    var powerScore: Int { atk * 3 + def * 5 + hpMax }
}

// MARK: - Kẻ địch
struct TNEnemy {
    var name: String
    var emoji: String
    var hp: Int
    var hpMax: Int
    var atk: Int
    var def: Int
    var reward: Int          // linh thạch
    var exp: Int
    var isBoss: Bool = false
    var frozen = false
    var stunned = false
}

// MARK: - Cốt truyện
struct TNChapter {
    let title: String
    let npc: String          // tên NPC dẫn truyện
    let npcEmoji: String
    let lines: [String]      // hội thoại (nguyên gốc, cảm hứng tu tiên)
    let boss: (name: String, emoji: String, hpMul: Double, atkMul: Double)
}
let TN_CHAPTERS: [TNChapter] = [
    TNChapter(title: "Chương 1 — Phàm Nhân Khởi Đầu", npc: "Đỗ Thanh Ý", npcEmoji: "🧚‍♀️",
              lines: ["Đỗ Thanh Ý: Vương Lâm ca ca, tư chất của ngươi tuy bình thường nhưng ý chí nghịch thiên hơn người!",
                      "Đỗ Thanh Ý: Muốn nhập Hàm Tiên Cổ Tông, trước hết phải hạ được Băng Hổ trấn giữ sơn môn.",
                      "Vương Lâm: Ta nhất định mạnh lên — để không ai có thể quyết định số phận của ta."],
              boss: ("Băng Hổ", "🐯", 1.0, 0.9)),
    TNChapter(title: "Chương 2 — Nhập Tông Tu Luyện", npc: "Lý Mộng Dao", npcEmoji: "👸",
              lines: ["Lý Mộng Dao: Ta thuần khiết mà kiên cường, đạo tâm chưa từng lung lay.",
                      "Lý Mộng Dao: Lôi Ưng ngoài kia nhanh như chớp — thắng nó, ngươi mới đủ tư cách bước tiếp."],
              boss: ("Lôi Ưng", "🦅", 1.3, 1.05)),
    TNChapter(title: "Chương 3 — Trúc Cơ Kiếp", npc: "Liễu Như Yên", npcEmoji: "🧝‍♀️",
              lines: ["Liễu Như Yên: Đan dược của ta có thể ổn định căn cơ, giúp ngươi vượt Trúc Cơ kiếp.",
                      "Liễu Như Yên: Nhưng La Sát — ma tu chiến thần — đang chặn đường. Cẩn thận sát khí của hắn!"],
              boss: ("La Sát", "🗡️", 1.7, 1.2)),
    TNChapter(title: "Chương 4 — Kết Đan Đại Điển", npc: "Mộc Dao", npcEmoji: "👩‍⚕️",
              lines: ["Mộc Dao: Y thuật của ta sẽ giữ mạng cho ngươi. Nhưng con đường phía trước phải tự ngươi bước.",
                      "Mộc Dao: Thanh Long thượng cổ uy nghiêm mạnh mẽ — vượt qua nó, Kim Đan của ngươi sẽ viên mãn!"],
              boss: ("Thanh Long", "🐉", 2.3, 1.15)),
    TNChapter(title: "Chương 5 — Nguyên Anh Xuất Thế", npc: "Đại Trưởng Lão", npcEmoji: "🧙",
              lines: ["Đại Trưởng Lão: Nguyên Anh là bước ngoặt sinh tử, thất bại thì hồn phi phách tán.",
                      "Đại Trưởng Lão: Thiên Hỏa Tôn Giả nóng nảy bộc trực nhưng hỏa đạo kinh thiên. Đây là quan ải thật sự!"],
              boss: ("Thiên Hỏa Tôn Giả", "🔥", 3.1, 1.35)),
    TNChapter(title: "Chương 6 — Hóa Thần Trảm Ma", npc: "Cổ Thần", npcEmoji: "👁️",
              lines: ["Cổ Thần: Ngươi mang khí tức của ta… kiêu ngạo mà mạnh mẽ, đúng là hữu duyên.",
                      "Cổ Thần: Tứ Diện Ma Nữ xảo quyệt độc ác đang gieo rắc tai ương. Trảm nó, chạm tới sức mạnh Cổ Thần!"],
              boss: ("Tứ Diện Ma Nữ", "😈", 4.2, 1.5)),
    TNChapter(title: "Chương 7 — Nghịch Thiên Cải Mệnh", npc: "Thiên Đạo", npcEmoji: "🌪️",
              lines: ["Thiên Đạo: Kẻ dám nghịch thiên… phải trả giá bằng cả sinh mệnh.",
                      "Vương Lâm: Ta tu tiên, chính là để NGHỊCH cái thiên mệnh này!"],
              boss: ("Thiên Kiếp Lôi Long", "🐲", 5.6, 1.7)),
]

// MARK: - Thư viện nhân vật (theo bộ ảnh roster)
struct TNChar: Identifiable { let id = UUID(); let name: String; let role: String; let emoji: String; let color: Color }
let TN_CHARACTERS: [(String, [TNChar])] = [
    ("👑 Nhân vật chính", [
        TNChar(name: "Vương Lâm", role: "Nhân vật chính · tư chất bình thường, ý chí nghịch thiên", emoji: "🥋", color: .yellow),
        TNChar(name: "Lý Mộng Dao", role: "Nữ chính · thuần khiết, kiên cường", emoji: "👸", color: .pink),
        TNChar(name: "Cổ Thần", role: "Thiên tài trẻ tuổi · kiêu ngạo, mạnh mẽ", emoji: "👁️", color: .cyan),
        TNChar(name: "Tư Vô Tà", role: "Tiên tôn cường giả · uy nghiêm, thâm tàng bất lộ", emoji: "🧙‍♂️", color: .orange),
        TNChar(name: "An Huyền", role: "Ma tu · tà ác, mưu mô", emoji: "🦹", color: .purple),
        TNChar(name: "Trịnh Hạo", role: "Thiên kiêu · phong lưu, tự cao", emoji: "🤴", color: .indigo),
    ]),
    ("⚔️ Thiên kiêu & Cường giả", [
        TNChar(name: "Đỗ Thanh Ý", role: "Linh đồng thông minh · có chút tinh quái", emoji: "🧚‍♀️", color: .green),
        TNChar(name: "Mục Trần", role: "Trưởng lão Nguyên Anh hậu kỳ", emoji: "🧔", color: .gray),
        TNChar(name: "Tử Linh", role: "Yêu khí · quyến rũ, nguy hiểm", emoji: "💃", color: .red),
        TNChar(name: "Nguyệt Nhi", role: "Thiên tài tu luyện · trung thành, thiện lương", emoji: "🌙", color: .purple),
        TNChar(name: "Lâm Thiên", role: "Thiên tài kiếm đạo · lạnh lùng, kiên định", emoji: "🗡️", color: .cyan),
    ]),
    ("🔥 Cường giả hàng đầu", [
        TNChar(name: "Thiên Đạo", role: "Quy tắc chí cao", emoji: "🌪️", color: .yellow),
        TNChar(name: "Đại Trưởng Lão", role: "Tông môn trưởng lão · trầm ổn, đáng kính", emoji: "🧙", color: .gray),
        TNChar(name: "La Sát", role: "Ma tu chiến thần · tàn bạo, vô tình", emoji: "🗡️", color: .red),
        TNChar(name: "Thiên Hỏa Tôn Giả", role: "Hỏa đạo cường giả · nóng nảy, bộc trực", emoji: "🔥", color: .orange),
        TNChar(name: "Bạch Y", role: "Sát thủ bí ẩn · lạnh như băng", emoji: "🥷", color: .white),
        TNChar(name: "Hồng Diệp", role: "Yêu tộc công chúa · kiêu sa, mạnh mẽ", emoji: "🦊", color: .pink),
    ]),
    ("🌸 Thánh nữ & Nữ cường giả", [
        TNChar(name: "Phong Lan", role: "Tùy tùng của Vương Lâm · trung thành, lanh lợi", emoji: "🌺", color: .teal),
        TNChar(name: "Liễu Như Yên", role: "Đan đạo thiên tài · ôn nhu, thông minh", emoji: "🧝‍♀️", color: .mint),
        TNChar(name: "Mộc Dao", role: "Y thuật cao siêu · từ tâm, thiện lương", emoji: "👩‍⚕️", color: .green),
        TNChar(name: "Hắc Y Nương", role: "Sát thủ thần bí · độc lập, lạnh lùng", emoji: "🖤", color: .purple),
        TNChar(name: "Dao Dao", role: "Linh thú hóa hình · ngây thơ, đáng yêu", emoji: "🦌", color: .orange),
    ]),
    ("🐉 Linh thú & Yêu thú", [
        TNChar(name: "Tiểu Huyền", role: "Linh thú · tinh nghịch, đáng yêu", emoji: "🐱", color: .cyan),
        TNChar(name: "Thanh Long", role: "Thánh thú · uy nghiêm, mạnh mẽ", emoji: "🐉", color: .blue),
        TNChar(name: "Hỏa Phượng", role: "Thánh thú · kiêu hãnh, rực rỡ", emoji: "🔥", color: .red),
        TNChar(name: "Băng Hổ", role: "Thánh thú · lạnh lùng, tàn bạo", emoji: "🐯", color: .cyan),
        TNChar(name: "Lôi Ưng", role: "Thánh thú · nhanh nhẹn, sắc bén", emoji: "🦅", color: .yellow),
        TNChar(name: "Kim Ô", role: "Thánh thú · cao quý, bất phàm", emoji: "🐦‍🔥", color: .orange),
    ]),
]
