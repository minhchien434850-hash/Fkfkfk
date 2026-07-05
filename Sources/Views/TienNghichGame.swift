import SwiftUI
import UIKit

// Rung phản hồi khi tung chiêu (cho game "đã tay")
enum TNHaptic {
    static func hit(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let g = UIImpactFeedbackGenerator(style: style); g.prepare(); g.impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// Hiệu ứng NHẤN nút: thu nhỏ + phát sáng khi bấm (áp cho nút skill, điều hướng…)
struct TNPress: ButtonStyle {
    var glow: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .shadow(color: glow.opacity(configuration.isPressed ? 0.9 : 0.0), radius: configuration.isPressed ? 12 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// ============================================================================
//  🐉 TIÊN NGHỊCH — game nhập vai tu tiên (single-player) trong app KENIOS.
//  Cảnh giới tu luyện · chiến đấu theo lượt · hiệu ứng tung chiêu/skill/skin ·
//  cốt truyện + NPC. Lưu tiến trình bằng UserDefaults. (Nằm trong Khám phá.)
//  Muốn gắn ẢNH nhân vật thật: thêm ảnh vào Assets tên "tn_vuonglam" (và
//  "tn_<npc>") — game tự dùng nếu có, không thì vẽ hào quang thay thế.
// ============================================================================

// MARK: - Cảnh giới tu luyện
enum TNRealm: Int, Codable, CaseIterable {
    case luyenKhi, trucCo, ketDan, nguyenAnh, hoaThan, anhBien, vanDinh, coThan
    var name: String {
        switch self {
        case .luyenKhi:  return "Luyện Khí"
        case .trucCo:    return "Trúc Cơ"
        case .ketDan:    return "Kết Đan"
        case .nguyenAnh: return "Nguyên Anh"
        case .hoaThan:   return "Hóa Thần"
        case .anhBien:   return "Anh Biến"
        case .vanDinh:   return "Vấn Đỉnh"
        case .coThan:    return "Cổ Thần"
        }
    }
    var color: Color {
        switch self {
        case .luyenKhi:  return Color(red: 0.55, green: 0.75, blue: 0.55)
        case .trucCo:    return Color(red: 0.35, green: 0.7, blue: 0.9)
        case .ketDan:    return Color(red: 0.95, green: 0.7, blue: 0.2)
        case .nguyenAnh: return Color(red: 0.65, green: 0.45, blue: 0.95)
        case .hoaThan:   return Color(red: 0.95, green: 0.35, blue: 0.55)
        case .anhBien:   return Color(red: 0.2, green: 0.85, blue: 0.8)
        case .vanDinh:   return Color(red: 1.0, green: 0.55, blue: 0.1)
        case .coThan:    return Color(red: 1.0, green: 0.85, blue: 0.2)
        }
    }
}

// MARK: - Kỹ năng (skill) + hiệu ứng
struct TNSkill: Identifiable {
    let id: String
    let name: String
    let mp: Int
    let power: Double        // hệ số sát thương theo Công
    let element: String      // kiem · loi · bang · huyet · than
    let unlockRealm: Int
    let desc: String
    var icon: String {
        switch element {
        case "kiem":  return "☄️"
        case "loi":   return "⚡"
        case "bang":  return "❄️"
        case "huyet": return "🩸"
        case "than":  return "🌟"
        default:      return "✦"
        }
    }
    var color: Color {
        switch element {
        case "kiem":  return .cyan
        case "loi":   return .yellow
        case "bang":  return Color(red: 0.5, green: 0.8, blue: 1.0)
        case "huyet": return .red
        case "than":  return Color(red: 1.0, green: 0.85, blue: 0.2)
        default:      return .white
        }
    }
}

let TN_ALL_SKILLS: [TNSkill] = [
    TNSkill(id: "kiem",  name: "Ngự Kiếm Thuật",  mp: 8,  power: 1.25, element: "kiem",  unlockRealm: 0,
            desc: "Điều khiển phi kiếm chém địch. Sát thương ổn định, tốn ít linh lực."),
    TNSkill(id: "loi",   name: "Thiên Lôi Chưởng", mp: 22, power: 1.9,  element: "loi",   unlockRealm: 1,
            desc: "Triệu sấm sét giáng xuống, có thể làm địch tê liệt (choáng)."),
    TNSkill(id: "bang",  name: "Băng Phong Nhận",  mp: 30, power: 2.1,  element: "bang",  unlockRealm: 2,
            desc: "Băng hàn cắt xé, đóng băng khiến địch bỏ lượt."),
    TNSkill(id: "huyet", name: "Huyết Hồn Phệ",    mp: 42, power: 2.5,  element: "huyet", unlockRealm: 3,
            desc: "Nuốt huyết khí đối thủ, hồi máu cho bản thân theo sát thương."),
    TNSkill(id: "than",  name: "Cổ Thần Chi Nộ",   mp: 80, power: 4.2,  element: "than",  unlockRealm: 5,
            desc: "Sức mạnh Cổ Thần bùng nổ — tuyệt kỹ hủy diệt, sát thương cực lớn."),
]
func tnSkill(_ id: String) -> TNSkill { TN_ALL_SKILLS.first { $0.id == id } ?? TN_ALL_SKILLS[0] }

// MARK: - Skin / Hào quang
struct TNSkin: Identifiable {
    let id: String
    let name: String
    let price: Int
    let colors: [Color]
    let desc: String
}
let TN_SKINS: [TNSkin] = [
    TNSkin(id: "default", name: "Phàm Nhân Y", price: 0,     colors: [.gray, Color(white: 0.35)], desc: "Bộ đồ vải thô thuở còn là phàm nhân."),
    TNSkin(id: "thanhvan",name: "Thanh Vân Bào", price: 300, colors: [.cyan, .blue], desc: "Áo bào xanh mây, linh khí lưu chuyển."),
    TNSkin(id: "tim",     name: "Tử Hà Thần Y", price: 800, colors: [Color(red:0.6,green:0.4,blue:0.95), .purple], desc: "Thần y tím, hào quang tử hà bao phủ."),
    TNSkin(id: "huyet",   name: "Huyết Long Giáp", price: 1500, colors: [.red, Color(red:0.5,green:0,blue:0)], desc: "Giáp huyết long, sát khí ngút trời."),
    TNSkin(id: "cothan",  name: "Cổ Thần Kim Thân", price: 4000, colors: [Color(red:1,green:0.85,blue:0.2), .orange], desc: "Kim thân Cổ Thần, ánh vàng chói lọi bất diệt."),
]
func tnSkin(_ id: String) -> TNSkin { TN_SKINS.first { $0.id == id } ?? TN_SKINS[0] }

// MARK: - Môn phái
struct TNSect: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let desc: String
    let colors: [Color]
    let atkMul: Double
    let defMul: Double
    let hpMul: Double
    let startSkill: String
    let skin: String
}
let TN_SECTS: [TNSect] = [
    TNSect(id: "hamtien", name: "Hàm Tiên Cổ Tông", emoji: "⚔️",
           desc: "Kiếm tu chính đạo · công kích cao, ngự kiếm sát địch từ xa.",
           colors: [.cyan, .blue], atkMul: 1.18, defMul: 1.0, hpMul: 1.0, startSkill: "kiem", skin: "thanhvan"),
    TNSect(id: "thiendao", name: "Thiên Đạo Các", emoji: "⚡",
           desc: "Pháp tu lôi hệ · điều khiển sấm sét, cân bằng công thủ.",
           colors: [.yellow, .orange], atkMul: 1.08, defMul: 1.05, hpMul: 1.05, startSkill: "loi", skin: "tim"),
    TNSect(id: "matoc", name: "Ma Tộc", emoji: "🩸",
           desc: "Ma tu huyết đạo · hút sinh lực đối thủ, càng đánh càng khỏe.",
           colors: [.red, Color(red:0.5,green:0,blue:0)], atkMul: 1.12, defMul: 0.92, hpMul: 1.08, startSkill: "huyet", skin: "huyet"),
    TNSect(id: "yeutoc", name: "Yêu Tộc", emoji: "❄️",
           desc: "Yêu tu luyện thể · phòng thủ cực cao, băng hàn khống chế.",
           colors: [Color(red:0.5,green:0.8,blue:1.0), .teal], atkMul: 0.96, defMul: 1.22, hpMul: 1.18, startSkill: "bang", skin: "thanhvan"),
    TNSect(id: "thanhdia", name: "Thánh Địa", emoji: "🌿",
           desc: "Đan/Y tu · máu trâu, hồi phục mạnh, bền bỉ trường kỳ.",
           colors: [.green, .mint], atkMul: 0.92, defMul: 1.12, hpMul: 1.28, startSkill: "kiem", skin: "default"),
]
func tnSect(_ id: String) -> TNSect { TN_SECTS.first { $0.id == id } ?? TN_SECTS[0] }

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
    var chapter = 0          // cốt truyện đã qua
    var arenaRank = 0        // số cao thủ đã hạ ở Đấu Đài
    var skin = "default"
    var ownedSkins = ["default"]
    var skills = ["kiem"]

    private var tier: Int { realm * 9 + stage }
    private var sectAtk: Double { tnSect(sect).atkMul }
    private var sectDef: Double { tnSect(sect).defMul }
    private var sectHp: Double { tnSect(sect).hpMul }

    var levelExpMax: Int { level * 120 }
    var isMaxLevel: Bool { level >= 100 }
    var expMax: Int { 80 + tier * 45 }
    var hpMax: Int { Int(Double(120 + tier * 70 + level * 22) * sectHp) }
    var mpMax: Int { 60 + tier * 40 + level * 6 }
    var atk: Int { Int(Double(18 + tier * 12 + level * 4) * sectAtk) }
    var def: Int { Int(Double(4 + tier * 4 + level) * sectDef) }
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

// MARK: - Engine
@MainActor
final class TNGame: ObservableObject {
    @Published var s = TNSave()
    private let key = "tn_save_v1"

    init() { load() }
    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode(TNSave.self, from: d) { s = v }
        if s.hp <= 0 || s.hp > s.hpMax { s.hp = s.hpMax }
    }
    func save() {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }

    // Thiền/tu luyện → nhận EXP
    func meditate() {
        let gain = max(6, s.expMax / 12)
        s.exp = min(s.exp + gain, s.expMax)
        save()
    }
    // Đột phá cảnh giới
    @discardableResult
    func breakthrough() -> String {
        guard s.canBreakthrough else { return "Chưa đủ tu vi để đột phá." }
        s.exp = 0
        if s.stage >= 9 {
            if s.realm < TNRealm.allCases.count - 1 {
                s.realm += 1; s.stage = 1
                s.hp = s.hpMax
                unlockSkillsForRealm()
                save()
                return "🎉 ĐỘT PHÁ THÀNH CÔNG! Bước vào cảnh giới \(s.realmEnum.name) tầng 1!"
            } else {
                s.stage = 9
                save()
                return "Ngươi đã đạt đỉnh cao Cổ Thần — vô địch thiên hạ!"
            }
        } else {
            s.stage += 1
            s.hp = s.hpMax
            unlockSkillsForRealm()
            save()
            return "✨ Tu vi tăng tiến — \(s.realmEnum.name) tầng \(s.stage)!"
        }
    }
    func unlockSkillsForRealm() {
        for sk in TN_ALL_SKILLS where sk.unlockRealm <= s.realm && !s.skills.contains(sk.id) {
            s.skills.append(sk.id)
        }
    }
    // Nhận exp CẤP ĐỘ (1–100). Trả về số cấp vừa lên.
    @discardableResult
    func gainLevelExp(_ amount: Int) -> Int {
        guard !s.isMaxLevel else { s.levelExp = 0; save(); return 0 }
        var up = 0
        s.levelExp += max(0, amount)
        while !s.isMaxLevel && s.levelExp >= s.levelExpMax {
            s.levelExp -= s.levelExpMax
            s.level += 1
            up += 1
            s.hp = s.hpMax           // lên cấp hồi đầy máu
        }
        if s.isMaxLevel { s.levelExp = 0 }
        save()
        return up
    }
    func reward(linhThach: Int, exp: Int) {
        s.linhThach += linhThach
        s.exp = min(s.exp + exp, s.expMax)
        gainLevelExp(exp)            // đánh quái cũng lên CẤP
        save()
    }
    func buySkin(_ skin: TNSkin) -> Bool {
        guard !s.ownedSkins.contains(skin.id), s.linhThach >= skin.price else { return false }
        s.linhThach -= skin.price
        s.ownedSkins.append(skin.id)
        s.skin = skin.id
        save(); return true
    }
    func equipSkin(_ id: String) { if s.ownedSkins.contains(id) { s.skin = id; save() } }
    func heal() { s.hp = s.hpMax; save() }

    // Tạo nhân vật mới (server + tên + môn phái)
    func createCharacter(name: String, server: String, sect: TNSect) {
        var v = TNSave()
        v.created = true
        v.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Vương Lâm" : String(name.prefix(16))
        v.server = server
        v.sect = sect.id
        var sk = [sect.startSkill]
        if !sk.contains("kiem") { sk.insert("kiem", at: 0) }   // ai cũng có kiếm cơ bản
        v.skills = sk
        v.skin = sect.skin
        v.ownedSkins = ["default"]
        if sect.skin != "default" { v.ownedSkins.append(sect.skin) }
        v.hp = v.hpMax
        s = v
        save()
    }
    func resetGame() { s = TNSave(); save() }
}

// MARK: - Root
struct TienNghichGameView: View {
    @StateObject private var game = TNGame()
    @State private var tab = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.13),
                                    game.s.realmEnum.color.opacity(0.28),
                                    Color(red: 0.02, green: 0.03, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            if !game.s.created {
                TNCreateView(game: game)
            } else {
                VStack(spacing: 0) {
                    Group {
                        switch tab {
                        case 0: TNHomeView(game: game, tab: $tab)
                        case 1: TNQuestView(game: game)
                        case 2: TNStoryView(game: game)
                        case 3: TNSkillsView(game: game)
                        default: TNShopView(game: game)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    TNTabBar(tab: $tab)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Tiên Nghịch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Thanh tab dưới
struct TNTabBar: View {
    @Binding var tab: Int
    private let items = [("Tu Luyện", "figure.mind.and.body"), ("Nhiệm Vụ", "list.bullet.clipboard.fill"),
                         ("Cốt Truyện", "book.fill"), ("Kỹ Năng", "flame.fill"), ("Cửa Hàng", "bag.fill")]
    var body: some View {
        HStack {
            ForEach(items.indices, id: \.self) { i in
                Button { withAnimation(.spring(response: 0.3)) { tab = i } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].1).font(.system(size: 18))
                        Text(items[i].0).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(tab == i ? Color.yellow : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(tab == i ? 1.12 : 1.0)
                }
                .buttonStyle(TNPress(glow: .yellow))
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Nền mây trôi
struct TNCloudsBG: View {
    @State private var move = false
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.06), .clear], center: .center, startRadius: 0, endRadius: 160))
                    .frame(width: 320, height: 320)
                    .offset(x: move ? CGFloat(i * 40 - 60) : CGFloat(-i * 40 + 60),
                            y: CGFloat(i * 180 - 200))
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { move.toggle() } }
        .allowsHitTesting(false)
    }
}

// MARK: - Avatar hào quang (dùng ảnh Assets nếu có "tn_vuonglam")
struct TNHeroAvatar: View {
    let skin: TNSkin
    let realm: TNRealm
    var size: CGFloat = 130
    @State private var pulse = false
    var body: some View {
        ZStack {
            // Hào quang xoay + nhấp nháy
            Circle()
                .fill(RadialGradient(colors: [skin.colors.first!.opacity(0.9), realm.color.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .blur(radius: 6)
            Circle()
                .strokeBorder(AngularGradient(colors: skin.colors + [skin.colors.first!], center: .center), lineWidth: 3)
                .frame(width: size * 1.15, height: size * 1.15)
                .rotationEffect(.degrees(pulse ? 360 : 0))
            // Nhân vật
            if let ui = UIImage(named: "tn_vuonglam") {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
            } else {
                Circle().fill(LinearGradient(colors: skin.colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .overlay(Text("🥋").font(.system(size: size * 0.5)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Thanh máu/mp
struct TNBar: View {
    var value: Int
    var maxValue: Int
    var colors: [Color]
    var label: String
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.4))
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, g.size.width * CGFloat(Double(value) / Double(max(1, maxValue)))))
                    .animation(.easeOut(duration: 0.35), value: value)
                Text("\(label) \(max(0,value))/\(maxValue)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.leading, 8)
            }
        }
        .frame(height: 16)
    }
}

// MARK: - HOME (tu luyện)
struct TNHomeView: View {
    @ObservedObject var game: TNGame
    @Binding var tab: Int
    @State private var toast: String?
    @State private var meditating = false
    @State private var showBattle = false
    @State private var showChars = false
    @State private var showArena = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Banner ảnh thế giới tu tiên (ảnh nhân vật do hoàng thượng cung cấp)
                if let ui = UIImage(named: "tn_hero") {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(height: 150).frame(maxWidth: .infinity).clipped()
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                        .overlay(alignment: .bottom) {
                            Text("TIÊN NGHỊCH").font(.system(size: 30, weight: .black, design: .serif))
                                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .white], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: .black, radius: 6).padding(.bottom, 8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal).padding(.top, 6)
                } else {
                    Text("TIÊN NGHỊCH").font(.system(size: 26, weight: .black, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .white], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .orange.opacity(0.6), radius: 8)
                        .padding(.top, 8)
                }

                TNHeroAvatar(skin: tnSkin(game.s.skin), realm: game.s.realmEnum)
                    .scaleEffect(meditating ? 1.06 : 1.0)

                Text(game.s.name).font(.title2.bold()).foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(game.s.realmEnum.name).bold()
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(game.s.realmEnum.color.opacity(0.35), in: Capsule())
                        .overlay(Capsule().strokeBorder(game.s.realmEnum.color, lineWidth: 1))
                    Text("Tầng \(game.s.stage)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    Text("⭐ Cấp \(game.s.level)").font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.25), in: Capsule())
                        .overlay(Capsule().strokeBorder(.yellow, lineWidth: 1))
                }
                .foregroundStyle(.white)

                // Chỉ số
                VStack(spacing: 8) {
                    TNBar(value: game.s.hp, maxValue: game.s.hpMax, colors: [.green, .mint], label: "❤️")
                    TNBar(value: game.s.exp, maxValue: game.s.expMax, colors: [.yellow, .orange], label: "Tu vi")
                    HStack {
                        stat("⚔️ Công", "\(game.s.atk)")
                        stat("🛡️ Thủ", "\(game.s.def)")
                        stat("💎 Linh thạch", "\(game.s.linhThach)")
                    }
                }
                .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Nút hành động
                VStack(spacing: 10) {
                    Button {
                        meditating = true
                        game.meditate()
                        withAnimation(.spring()) {}
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { meditating = false }
                        toastMsg("🧘 Thiền định — tu vi +\(max(6, game.s.expMax/12))")
                    } label: { bigBtn("🧘 Tu Luyện (thiền lấy tu vi)", [.teal, .blue]) }.buttonStyle(TNPress(glow: .teal))

                    if game.s.canBreakthrough {
                        Button {
                            toastMsg(game.breakthrough())
                        } label: { bigBtn("⚡ ĐỘT PHÁ CẢNH GIỚI!", [.orange, .red]) }.buttonStyle(TNPress(glow: .orange))
                            .shadow(color: .orange, radius: 10)
                    }

                    Button { showBattle = true } label: { bigBtn("⚔️ Phiêu Lưu — Luyện Yêu Thú", [.purple, .indigo]) }.buttonStyle(TNPress(glow: .purple))
                    Button { tab = 1 } label: { bigBtn("📖 Đi Theo Cốt Truyện", [.brown, .orange]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showArena = true } label: { bigBtn("🏆 Đấu Đài — Thách Đấu Cao Thủ", [.yellow, .orange]) }.buttonStyle(TNPress(glow: .yellow))
                    Button { showChars = true } label: { bigBtn("🖼️ Thư Viện Nhân Vật", [.pink, .purple]) }.buttonStyle(TNPress(glow: .pink))
                }
                .padding(.horizontal)

                if let toast {
                    Text(toast).font(.footnote.bold()).foregroundStyle(.yellow)
                        .padding(10).background(.black.opacity(0.5), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                Color.clear.frame(height: 20)
            }
        }
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: makeWildEnemy(), storyMode: false, onDone: { _ in })
        }
        .sheet(isPresented: $showChars) { TNCharactersView() }
        .fullScreenCover(isPresented: $showArena) { TNArenaView(game: game) }
    }

    private func toastMsg(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if toast == m { toast = nil } } }
    }
    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Text(v).font(.subheadline.bold()).foregroundStyle(.white)
        }.frame(maxWidth: .infinity)
    }
    private func bigBtn(_ t: String, _ c: [Color]) -> some View {
        Text(t).font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(LinearGradient(colors: c, startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14))
    }
    private func makeWildEnemy() -> TNEnemy {
        let names = [("Băng Hổ", "🐯"), ("Lôi Ưng", "🦅"), ("Huyền Vũ", "🐢"), ("Hắc Điệp", "🦋"), ("Kim Ô", "🐦‍🔥"), ("Hỏa Phượng", "🔥")]
        let n = names.randomElement()!
        let lvl = Double(game.s.realm * 9 + game.s.stage)
        let hp = Int(80 + lvl * 90 * Double.random(in: 0.85...1.15))
        return TNEnemy(name: n.0, emoji: n.1, hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * Double.random(in: 0.55...0.8)),
                       def: Int(Double(game.s.def) * 0.6),
                       reward: Int(30 + lvl * 12), exp: Int(20 + lvl * 15))
    }
}

// MARK: - Hiệu ứng tung chiêu
struct TNSkillFX: View {
    let color: Color
    let icon: String
    @State private var burst = false
    var body: some View {
        ZStack {
            color.opacity(burst ? 0.0 : 0.35).ignoresSafeArea()
            ForEach(0..<14, id: \.self) { i in
                Text(icon).font(.system(size: 26))
                    .offset(x: burst ? CGFloat.random(in: -160...160) : 0,
                            y: burst ? CGFloat.random(in: -220...120) : 0)
                    .opacity(burst ? 0 : 1)
                    .scaleEffect(burst ? 1.6 : 0.3)
            }
            Circle().stroke(color, lineWidth: 4).frame(width: burst ? 340 : 20, height: burst ? 340 : 20)
                .opacity(burst ? 0 : 1)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { burst = true } }
        .allowsHitTesting(false)
    }
}

struct TNDamageText: View {
    let text: String
    let color: Color
    @State private var up = false
    var body: some View {
        Text(text).font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(color).shadow(color: .black, radius: 3)
            .offset(y: up ? -90 : 0).opacity(up ? 0 : 1).scaleEffect(up ? 1.3 : 0.6)
            .onAppear { withAnimation(.easeOut(duration: 0.9)) { up = true } }
    }
}

// MARK: - Chiến đấu
struct TNBattleView: View {
    @ObservedObject var game: TNGame
    @State var enemy: TNEnemy
    let storyMode: Bool
    let onDone: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mp = 0
    @State private var log = "Trận chiến bắt đầu!"
    @State private var fx: (Color, String)?
    @State private var dmg: (String, Color)?
    @State private var enemyDmg: (String, Color)?
    @State private var shake = false
    @State private var ended = false
    @State private var win = false
    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.08,green:0.04,blue:0.14), Color(red:0.02,green:0.02,blue:0.06)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            VStack(spacing: 14) {
                // Địch
                VStack(spacing: 6) {
                    Text(enemy.isBoss ? "👑 BOSS" : "Yêu thú").font(.caption).foregroundStyle(.red)
                    Text(enemy.emoji).font(.system(size: 66))
                        .offset(x: shake ? 10 : 0)
                        .overlay(enemy.frozen ? Text("❄️").font(.system(size: 40)).offset(y: -30) : nil)
                    Text(enemy.name).font(.headline).foregroundStyle(.white)
                    TNBar(value: enemy.hp, maxValue: enemy.hpMax, colors: [.red, .orange], label: "HP").frame(width: 220)
                    if let enemyDmg { TNDamageText(text: enemyDmg.0, color: enemyDmg.1).id(enemyDmg.0 + UUID().uuidString) }
                }
                .padding(.top, 30)

                Spacer()

                // Người chơi
                VStack(spacing: 6) {
                    if let dmg { TNDamageText(text: dmg.0, color: dmg.1).id(dmg.0 + UUID().uuidString) }
                    TNHeroAvatar(skin: tnSkin(game.s.skin), realm: game.s.realmEnum, size: 84)
                    Text("\(game.s.name) — \(game.s.realmEnum.name)").font(.subheadline).foregroundStyle(.white)
                    TNBar(value: game.s.hp, maxValue: game.s.hpMax, colors: [.green, .mint], label: "❤️").frame(width: 240)
                    TNBar(value: mp, maxValue: game.s.mpMax, colors: [.blue, .cyan], label: "🔷").frame(width: 240)
                }

                // Nhật ký
                Text(log).font(.caption).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 34).padding(.horizontal)
                    .multilineTextAlignment(.center)

                // Kỹ năng
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        skillBtn(nil)   // đánh thường
                        ForEach(game.s.skills, id: \.self) { id in skillBtn(tnSkill(id)) }
                        meditateBtn()
                    }.padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
            .offset(x: shake ? -6 : 0)

            if let fx { TNSkillFX(color: fx.0, icon: fx.1).id(UUID()) }

            if ended {
                TNResultView(win: win, reward: win ? enemy.reward : 0, exp: win ? enemy.exp : 0) {
                    onDone(win); dismiss()
                }
            }
        }
        .onAppear { mp = game.s.mpMax }
    }

    private func skillBtn(_ sk: TNSkill?) -> some View {
        let usable = sk == nil || mp >= sk!.mp
        return Button {
            if sk == nil { basicAttack() } else { useSkill(sk!) }
        } label: {
            VStack(spacing: 3) {
                Text(sk?.icon ?? "👊").font(.system(size: 24))
                Text(sk?.name ?? "Đánh thường").font(.system(size: 9, weight: .semibold)).lineLimit(1)
                if let sk { Text("🔷\(sk.mp)").font(.system(size: 8)) }
            }
            .foregroundStyle(.white)
            .frame(width: 82, height: 74)
            .background((sk?.color ?? .gray).opacity(usable ? 0.35 : 0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder((sk?.color ?? .gray).opacity(usable ? 0.9 : 0.3), lineWidth: 1))
        }
        .buttonStyle(TNPress(glow: sk?.color ?? .white))
        .disabled(busy || ended || !usable)
    }
    private func meditateBtn() -> some View {
        Button { restoreMP() } label: {
            VStack(spacing: 3) {
                Text("🧘").font(.system(size: 24))
                Text("Vận Khí").font(.system(size: 9, weight: .semibold))
                Text("+MP").font(.system(size: 8))
            }.foregroundStyle(.white).frame(width: 82, height: 74)
            .background(Color.teal.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(TNPress(glow: .teal)).disabled(busy || ended)
    }

    private func basicAttack() {
        let d = max(3, Int(Double(game.s.atk) * Double.random(in: 0.7...0.95)) - enemy.def)
        fx = (.gray, "👊")
        TNHaptic.hit(.light)
        hitEnemy(d, "\(game.s.name) vung quyền!", .white)
    }
    private func useSkill(_ sk: TNSkill) {
        guard mp >= sk.mp else { return }
        mp -= sk.mp
        var d = max(5, Int(Double(game.s.atk) * sk.power * Double.random(in: 0.9...1.15)) - enemy.def)
        fx = (sk.color, sk.icon)
        TNHaptic.hit(sk.element == "than" ? .heavy : .medium)
        var extra = ""
        switch sk.element {
        case "loi":   if Bool.random() { enemy.stunned = true; extra = " ⚡Địch bị choáng!" }
        case "bang":  if Double.random(in: 0...1) < 0.55 { enemy.frozen = true; extra = " ❄️Địch bị đóng băng!" }
        case "huyet": let heal = d / 3; game.s.hp = min(game.s.hpMax, game.s.hp + heal); extra = " 🩸Hút \(heal) máu!"
        case "than":  d = Int(Double(d) * 1.15); extra = " 🌟Cổ Thần chi lực bùng nổ!"
        default: break
        }
        hitEnemy(d, "\(sk.name)!\(extra)", sk.color)
    }
    private func restoreMP() {
        mp = min(game.s.mpMax, mp + game.s.mpMax / 3)
        log = "🧘 Vận khí điều tức — linh lực hồi phục."
        enemyTurn()
    }

    private func hitEnemy(_ d: Int, _ msg: String, _ color: Color) {
        busy = true
        enemy.hp = max(0, enemy.hp - d)
        enemyDmg = ("-\(d)", color)
        log = msg
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { shake.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shake = false; fx = nil }
        if enemy.hp <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                game.reward(linhThach: enemy.reward, exp: enemy.exp)
                TNHaptic.success()
                win = true; ended = true
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { enemyTurn() }
    }
    private func enemyTurn() {
        if enemy.frozen { enemy.frozen = false; log = "❄️ \(enemy.name) bị đóng băng, bỏ lượt!"; busy = false; game.save(); return }
        if enemy.stunned { enemy.stunned = false; log = "⚡ \(enemy.name) bị choáng, không thể tấn công!"; busy = false; game.save(); return }
        let d = max(2, enemy.atk - Int(Double(game.s.def) * Double.random(in: 0.8...1.0)))
        game.s.hp = max(0, game.s.hp - d)
        dmg = ("-\(d)", .red)
        log = "\(enemy.emoji) \(enemy.name) phản công gây \(d) sát thương!"
        game.save()
        if game.s.hp <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { win = false; ended = true; game.heal() }
        } else { busy = false }
    }
}

struct TNResultView: View {
    let win: Bool
    let reward: Int
    let exp: Int
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(win ? "🎉 CHIẾN THẮNG!" : "💀 THẤT BẠI").font(.largeTitle.bold())
                    .foregroundStyle(win ? .yellow : .red)
                if win {
                    Text("💎 Linh thạch +\(reward)").foregroundStyle(.cyan)
                    Text("✨ Tu vi +\(exp)").foregroundStyle(.orange)
                } else {
                    Text("Đạo hữu bại trận nhưng được cứu chữa,\nmáu đã hồi đầy. Luyện thêm rồi quay lại!")
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)).font(.footnote)
                }
                Button(action: onClose) {
                    Text("Trở về").font(.headline).foregroundStyle(.white)
                        .frame(width: 160).padding(.vertical, 12)
                        .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
            }
            .padding(30).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Cốt truyện
struct TNStoryView: View {
    @ObservedObject var game: TNGame
    @State private var showDialogue = false
    @State private var showBattle = false
    @State private var lineIdx = 0

    private var idx: Int { min(game.s.chapter, TN_CHAPTERS.count - 1) }
    private var ch: TNChapter { TN_CHAPTERS[idx] }
    private var finished: Bool { game.s.chapter >= TN_CHAPTERS.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("📖 CỐT TRUYỆN").font(.title2.bold()).foregroundStyle(.white).padding(.top, 10)
                if finished {
                    Text("🏆 Ngươi đã đi hết hành trình nghịch thiên hiện có!\nTruyền kỳ Vương Lâm sẽ còn tiếp tục ở bản sau…")
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85)).padding()
                } else {
                    VStack(spacing: 12) {
                        Text(ch.npcEmoji).font(.system(size: 60))
                        Text(ch.title).font(.headline).foregroundStyle(.yellow).multilineTextAlignment(.center)
                        Text("NPC: \(ch.npc)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Text("Trùm chương: \(ch.boss.emoji) \(ch.boss.name)").font(.footnote).foregroundStyle(.red)
                        Button { lineIdx = 0; showDialogue = true } label: {
                            Text("▶ Bắt đầu chương").font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing),
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                }
                // Tiến độ
                Text("Tiến độ: \(min(game.s.chapter, TN_CHAPTERS.count))/\(TN_CHAPTERS.count) chương")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .sheet(isPresented: $showDialogue) {
            TNDialogueView(ch: ch, onFinish: { showDialogue = false; showBattle = true })
        }
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: makeBoss(), storyMode: true) { won in
                if won && game.s.chapter <= idx { game.s.chapter = idx + 1; game.save() }
            }
        }
    }
    private func makeBoss() -> TNEnemy {
        let lvl = Double(game.s.realm * 9 + game.s.stage)
        let hp = Int((160 + lvl * 120) * ch.boss.hpMul)
        return TNEnemy(name: ch.boss.name, emoji: ch.boss.emoji, hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * 0.7 * ch.boss.atkMul),
                       def: Int(Double(game.s.def) * 0.8),
                       reward: Int(120 + lvl * 30), exp: Int(90 + lvl * 40), isBoss: true)
    }
}

struct TNDialogueView: View {
    let ch: TNChapter
    let onFinish: () -> Void
    @State private var i = 0
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.06,green:0.05,blue:0.12), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text(ch.npcEmoji).font(.system(size: 90))
                Text(ch.lines[min(i, ch.lines.count - 1)])
                    .font(.title3).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding().background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .id(i)
                    .transition(.opacity)
                Spacer()
                Button {
                    if i < ch.lines.count - 1 { withAnimation { i += 1 } } else { onFinish() }
                } label: {
                    Text(i < ch.lines.count - 1 ? "Tiếp ▶" : "⚔️ Vào trận!").font(.headline).foregroundStyle(.white)
                        .frame(width: 200).padding(.vertical, 13)
                        .background(LinearGradient(colors: [.purple, .orange], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Kỹ năng
struct TNSkillsView: View {
    @ObservedObject var game: TNGame
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("🔥 KỸ NĂNG").font(.title2.bold()).foregroundStyle(.white).padding(.top, 10)
                Text("Đột phá cảnh giới để mở khóa tuyệt kỹ mạnh hơn.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                ForEach(TN_ALL_SKILLS) { sk in
                    let owned = game.s.skills.contains(sk.id)
                    HStack(spacing: 12) {
                        Text(sk.icon).font(.system(size: 34))
                            .frame(width: 56, height: 56)
                            .background(sk.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sk.name).font(.headline).foregroundStyle(owned ? .white : .white.opacity(0.4))
                            Text(sk.desc).font(.caption2).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                            Text(owned ? "🔷 \(sk.mp) linh lực · Hệ số x\(String(format: "%.1f", sk.power))"
                                       : "🔒 Mở ở cảnh giới \(TNRealm(rawValue: sk.unlockRealm)?.name ?? "?")")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(owned ? sk.color : .gray)
                        }
                        Spacer()
                    }
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                Color.clear.frame(height: 20)
            }
        }
    }
}

// MARK: - Cửa hàng (skin/hào quang)
struct TNShopView: View {
    @ObservedObject var game: TNGame
    @State private var msg: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("🛍️ CỬA HÀNG").font(.title2.bold()).foregroundStyle(.white)
                    Spacer()
                    Text("💎 \(game.s.linhThach)").font(.headline).foregroundStyle(.cyan)
                }.padding(.horizontal).padding(.top, 10)
                Text("Đổi SKIN / hào quang — hiệu ứng ánh sáng nhân vật.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))

                ForEach(TN_SKINS) { sk in
                    let owned = game.s.ownedSkins.contains(sk.id)
                    let equipped = game.s.skin == sk.id
                    HStack(spacing: 12) {
                        Circle().fill(LinearGradient(colors: sk.colors, startPoint: .top, endPoint: .bottom))
                            .frame(width: 54, height: 54)
                            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
                            .shadow(color: sk.colors.first!.opacity(0.7), radius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sk.name).font(.headline).foregroundStyle(.white)
                            Text(sk.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if equipped {
                            Text("Đang mặc").font(.caption.bold()).foregroundStyle(.green)
                        } else if owned {
                            Button("Mặc") { game.equipSkin(sk.id) }
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(.blue, in: Capsule())
                        } else {
                            Button("💎\(sk.price)") {
                                if game.buySkin(sk) { flash("✅ Đã mua & mặc \(sk.name)!") }
                                else { flash("❌ Không đủ linh thạch!") }
                            }
                            .font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(game.s.linhThach >= sk.price ? Color.orange : Color.gray, in: Capsule())
                        }
                    }
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow) }
                Color.clear.frame(height: 20)
            }
        }
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Đấu Đài (leo tháp thách đấu cao thủ roster)
struct TNArenaFoe { let name: String; let emoji: String; let title: String; let hpMul: Double; let atkMul: Double }
let TN_ARENA: [TNArenaFoe] = [
    TNArenaFoe(name: "Trịnh Hạo", emoji: "🤴", title: "Thiên kiêu phong lưu", hpMul: 0.8, atkMul: 0.7),
    TNArenaFoe(name: "Mục Trần", emoji: "🧔", title: "Nguyên Anh hậu kỳ", hpMul: 1.1, atkMul: 0.85),
    TNArenaFoe(name: "Tử Linh", emoji: "💃", title: "Yêu khí nguy hiểm", hpMul: 1.3, atkMul: 1.0),
    TNArenaFoe(name: "Lâm Thiên", emoji: "🗡️", title: "Thiên tài kiếm đạo", hpMul: 1.6, atkMul: 1.15),
    TNArenaFoe(name: "An Huyền", emoji: "🦹", title: "Ma tu tà ác", hpMul: 2.0, atkMul: 1.3),
    TNArenaFoe(name: "La Sát", emoji: "🗡️", title: "Ma tu chiến thần", hpMul: 2.5, atkMul: 1.45),
    TNArenaFoe(name: "Thiên Hỏa Tôn Giả", emoji: "🔥", title: "Hỏa đạo cường giả", hpMul: 3.2, atkMul: 1.6),
    TNArenaFoe(name: "Tứ Diện Ma Nữ", emoji: "😈", title: "Ma tộc mỹ nhân", hpMul: 4.0, atkMul: 1.8),
    TNArenaFoe(name: "Cổ Thần", emoji: "👁️", title: "Thiên tài kiêu ngạo", hpMul: 5.0, atkMul: 2.0),
    TNArenaFoe(name: "Thiên Đạo", emoji: "🌪️", title: "Quy tắc chí cao", hpMul: 6.5, atkMul: 2.3),
]

struct TNArenaView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var showBattle = false
    @State private var foeIdx = 0
    @State private var toast: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.1,green:0.07,blue:0.02), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            VStack(spacing: 0) {
                HStack {
                    Text("🏆 ĐẤU ĐÀI").font(.title2.bold()).foregroundStyle(.yellow)
                    Spacer()
                    Button("Đóng") { dismiss() }.foregroundStyle(.white)
                }.padding()
                Text("Đã hạ \(game.s.arenaRank)/\(TN_ARENA.count) cao thủ — Danh hiệu: \(rankTitle)")
                    .font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 6)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(TN_ARENA.indices, id: \.self) { i in
                            let f = TN_ARENA[i]
                            let locked = i > game.s.arenaRank
                            let cleared = i < game.s.arenaRank
                            HStack(spacing: 12) {
                                Text(f.emoji).font(.system(size: 32))
                                    .frame(width: 54, height: 54)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(locked ? Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.7)) : nil)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ải \(i+1): \(f.name)").font(.subheadline.bold()).foregroundStyle(.white)
                                    Text(f.title).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                if cleared { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                                else if locked { Text("🔒").font(.caption) }
                                else {
                                    Button("Thách đấu") { foeIdx = i; showBattle = true }
                                        .font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(.orange, in: Capsule())
                                        .buttonStyle(TNPress(glow: .orange))
                                }
                            }
                            .padding(12)
                            .background((cleared ? Color.green.opacity(0.12) : Color.white.opacity(0.05)), in: RoundedRectangle(cornerRadius: 14))
                            .opacity(locked ? 0.5 : 1)
                            .padding(.horizontal)
                        }
                        Color.clear.frame(height: 20)
                    }
                }
                if let toast {
                    Text(toast).font(.footnote.bold()).foregroundStyle(.yellow)
                        .padding(10).background(.black.opacity(0.6), in: Capsule()).padding(.bottom, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: arenaEnemy(TN_ARENA[foeIdx]), storyMode: true) { won in
                if won && foeIdx == game.s.arenaRank {
                    game.s.arenaRank += 1; game.save()
                    withAnimation { toast = "🎉 Hạ gục \(TN_ARENA[foeIdx].name)! Danh hiệu mới: \(rankTitle)" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { toast = nil } }
                }
            }
        }
    }
    private var rankTitle: String {
        switch game.s.arenaRank {
        case 0: return "Vô Danh Tiểu Tốt"
        case 1...2: return "Sơ Nhập Giang Hồ"
        case 3...4: return "Tiểu Hữu Danh Khí"
        case 5...6: return "Nhất Phương Cao Thủ"
        case 7...8: return "Danh Chấn Thiên Hạ"
        case 9: return "Chí Tôn Cường Giả"
        default: return "🌟 NGHỊCH THIÊN ĐẠI ĐẾ"
        }
    }
    private func arenaEnemy(_ f: TNArenaFoe) -> TNEnemy {
        let base = Double(game.s.hpMax)
        let hp = Int(base * f.hpMul)
        return TNEnemy(name: f.name, emoji: f.emoji, hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * 0.75 * f.atkMul),
                       def: Int(Double(game.s.def) * 0.85),
                       reward: 150 + foeIdx * 120, exp: 120 + foeIdx * 60, isBoss: true)
    }
}

// MARK: - Tạo nhân vật (chọn server · nhập tên · chọn môn phái)
struct TNCreateView: View {
    @ObservedObject var game: TNGame
    @State private var step = 0
    @State private var name = ""
    @State private var server = "Thiên Nam"
    @State private var sect = "hamtien"

    private let servers: [(String, String, Int)] = [
        ("Thiên Nam", "🟢 Mượt", 1287), ("Bắc Cương", "🟢 Mượt", 964),
        ("Nam Cương", "🟡 Đông", 2510), ("Tây Vực", "🟢 Mượt", 733),
        ("Đông Hải", "🔴 Full", 3902), ("Tu Chân Giới", "🆕 Mới mở", 158),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tiêu đề
            VStack(spacing: 4) {
                Text("TIÊN NGHỊCH").font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .white], startPoint: .leading, endPoint: .trailing))
                    .shadow(color: .orange.opacity(0.6), radius: 8)
                Text(["① Chọn Máy Chủ", "② Đặt Đạo Hiệu", "③ Chọn Môn Phái"][step])
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }.padding(.top, 24).padding(.bottom, 12)

            ScrollView {
                switch step {
                case 0: serverStep
                case 1: nameStep
                default: sectStep
                }
            }

            // Nút điều hướng
            HStack(spacing: 12) {
                if step > 0 {
                    Button { withAnimation { step -= 1 } } label: {
                        Text("◀ Quay lại").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Button {
                    if step < 2 { withAnimation { step += 1 } }
                    else { game.createCharacter(name: name, server: server, sect: tnSect(sect)) }
                } label: {
                    Text(step < 2 ? "Tiếp ▶" : "⚔️ VÀO GAME").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .foregroundStyle(.white)
    }

    private var serverStep: some View {
        VStack(spacing: 10) {
            ForEach(servers, id: \.0) { sv in
                Button { server = sv.0 } label: {
                    HStack {
                        Image(systemName: "server.rack").foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sv.0).font(.headline)
                            Text("\(sv.1) · \(sv.2) đạo hữu online").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if server == sv.0 { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .padding(14)
                    .background((server == sv.0 ? Color.orange.opacity(0.25) : Color.white.opacity(0.06)),
                               in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(server == sv.0 ? Color.orange : .clear, lineWidth: 1.5))
                }
                .foregroundStyle(.white)
            }
        }.padding(.horizontal)
    }

    private var nameStep: some View {
        VStack(spacing: 16) {
            TNHeroAvatar(skin: tnSkin(tnSect(sect).skin), realm: .luyenKhi, size: 110).padding(.top, 20)
            Text("Nhập đạo hiệu của ngươi:").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            TextField("Vương Lâm", text: $name)
                .multilineTextAlignment(.center).font(.title3.bold())
                .padding().background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
            Text("Tối đa 16 ký tự. Để trống sẽ dùng \"Vương Lâm\".")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var sectStep: some View {
        VStack(spacing: 10) {
            ForEach(TN_SECTS) { sc in
                Button { sect = sc.id } label: {
                    HStack(spacing: 12) {
                        Text(sc.emoji).font(.system(size: 34))
                            .frame(width: 56, height: 56)
                            .background(LinearGradient(colors: sc.colors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sc.name).font(.headline)
                            Text(sc.desc).font(.caption2).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                            Text("⚔️x\(String(format:"%.2f",sc.atkMul)) · 🛡️x\(String(format:"%.2f",sc.defMul)) · ❤️x\(String(format:"%.2f",sc.hpMul))")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(sc.colors.first!)
                        }
                        Spacer()
                        if sect == sc.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .padding(12)
                    .background((sect == sc.id ? sc.colors.first!.opacity(0.22) : Color.white.opacity(0.06)),
                               in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sect == sc.id ? sc.colors.first! : .clear, lineWidth: 1.5))
                }
                .foregroundStyle(.white)
            }
        }.padding(.horizontal)
    }
}

// MARK: - Nhiệm vụ (làm nhiệm vụ tăng EXP cấp độ)
struct TNQuestView: View {
    @ObservedObject var game: TNGame
    @State private var toast: String?
    @State private var cooldowns: [String: Date] = [:]
    @State private var showBattle = false

    // (id, tên, mô tả, exp, linh thạch, loại) — loại: "instant" hoặc "battle"
    private var quests: [(String, String, String, Int, Int, String)] {
        let L = game.s.level
        return [
            ("thien", "🧘 Bế Quan Tu Luyện", "Ngồi thiền hấp thu linh khí.", 30 + L*8, 10 + L*2, "instant"),
            ("thao", "🌿 Hái Linh Thảo", "Vào Dược Viên hái thảo dược.", 22 + L*6, 18 + L*3, "instant"),
            ("dan", "🔥 Luyện Đan Dược", "Giúp Liễu Như Yên luyện đan.", 40 + L*10, 25 + L*4, "instant"),
            ("tuan", "🗺️ Tuần Tra Sơn Môn", "Bảo vệ tông môn khỏi tà tu.", 35 + L*9, 20 + L*3, "instant"),
            ("san", "⚔️ Săn Yêu Thú (thực chiến)", "Diệt yêu thú — thắng nhận nhiều EXP!", 90 + L*20, 60 + L*8, "battle"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("📜 NHIỆM VỤ").font(.title2.bold()).foregroundStyle(.white).padding(.top, 10)

                // Cấp độ
                VStack(spacing: 6) {
                    HStack {
                        Text("⭐ Cấp \(game.s.level)").font(.title3.bold()).foregroundStyle(.yellow)
                        Spacer()
                        Text(game.s.isMaxLevel ? "TỐI ĐA" : "EXP \(game.s.levelExp)/\(game.s.levelExpMax)")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    TNBar(value: game.s.isMaxLevel ? 1 : game.s.levelExp,
                          maxValue: game.s.isMaxLevel ? 1 : game.s.levelExpMax,
                          colors: [.yellow, .orange], label: "")
                }
                .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)

                Text("Làm nhiệm vụ để tăng EXP lên cấp (tối đa cấp 100).")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))

                ForEach(quests, id: \.0) { q in
                    let cd = cooldownLeft(q.0)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(q.1).font(.subheadline.bold()).foregroundStyle(.white)
                            Text(q.2).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Text("✨ EXP +\(q.3)  ·  💎 +\(q.4)").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        Button {
                            if q.5 == "battle" { showBattle = true }
                            else { doQuest(q) }
                        } label: {
                            Text(cd > 0 ? "\(cd)s" : "Làm")
                                .font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 60).padding(.vertical, 9)
                                .background(cd > 0 ? Color.gray : Color.green, in: Capsule())
                        }
                        .disabled(cd > 0)
                    }
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                }

                if let toast {
                    Text(toast).font(.footnote.bold()).foregroundStyle(.yellow)
                        .padding(10).background(.black.opacity(0.5), in: Capsule())
                }
                Color.clear.frame(height: 20)
            }
        }
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: questEnemy(), storyMode: false) { won in
                if won { flash("🎉 Hoàn thành! Nhận EXP + linh thạch.") }
            }
        }
    }

    private func cooldownLeft(_ id: String) -> Int {
        guard let t = cooldowns[id] else { return 0 }
        return max(0, 15 - Int(Date().timeIntervalSince(t)))
    }
    private func doQuest(_ q: (String, String, String, Int, Int, String)) {
        let up = game.gainLevelExp(q.3)
        game.s.linhThach += q.4
        game.save()
        cooldowns[q.0] = Date()
        flash(up > 0 ? "🎉 LÊN CẤP \(game.s.level)! " : "✨ +\(q.3) EXP · 💎 +\(q.4)")
    }
    private func questEnemy() -> TNEnemy {
        let names = [("Băng Hổ", "🐯"), ("Lôi Ưng", "🦅"), ("Hắc Điệp", "🦋"), ("Kim Ô", "🐦‍🔥")]
        let n = names.randomElement()!
        let lvl = Double(game.s.realm * 9 + game.s.stage + game.s.level / 5)
        let hp = Int(90 + lvl * 85)
        return TNEnemy(name: n.0, emoji: n.1, hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * 0.6), def: Int(Double(game.s.def) * 0.6),
                       reward: 60 + Int(lvl*8), exp: 90 + Int(lvl*20))
    }
    private func flash(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if toast == m { toast = nil } } }
    }
}

// MARK: - Thư viện nhân vật (ảnh roster + danh sách)
struct TNCharactersView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Ảnh roster đầy đủ (do hoàng thượng cung cấp)
                    if let ui = UIImage(named: "tn_roster") {
                        Image(uiImage: ui).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }
                    ForEach(TN_CHARACTERS.indices, id: \.self) { gi in
                        let group = TN_CHARACTERS[gi]
                        Text(group.0).font(.headline).foregroundStyle(.yellow).padding(.horizontal)
                        ForEach(group.1) { c in
                            HStack(spacing: 12) {
                                Text(c.emoji).font(.system(size: 30))
                                    .frame(width: 50, height: 50)
                                    .background(c.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.subheadline.bold()).foregroundStyle(.white)
                                    Text(c.role).font(.caption2).foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer()
                            }
                            .padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 10)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.13), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .navigationTitle("Thư Viện Nhân Vật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
}
