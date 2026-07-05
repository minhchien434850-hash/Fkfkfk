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

// MARK: - Cảnh giới tu luyện (15 cảnh giới lớn theo GDD)
enum TNRealm: Int, Codable, CaseIterable {
    case luyenKhi, trucCo, ketDan, nguyenAnh, hoaThan, anhBien, vanDinh,
         daiThua, doKiep, diaTien, thienTien, kimTien, daiLa, chuanThanh, coThan
    var name: String {
        switch self {
        case .luyenKhi:  return "Luyện Khí"
        case .trucCo:    return "Trúc Cơ"
        case .ketDan:    return "Kết Đan"
        case .nguyenAnh: return "Nguyên Anh"
        case .hoaThan:   return "Hóa Thần"
        case .anhBien:   return "Anh Biến"
        case .vanDinh:   return "Vấn Đỉnh"
        case .daiThua:   return "Đại Thừa"
        case .doKiep:    return "Độ Kiếp"
        case .diaTien:   return "Địa Tiên"
        case .thienTien: return "Thiên Tiên"
        case .kimTien:   return "Kim Tiên"
        case .daiLa:     return "Đại La Kim Tiên"
        case .chuanThanh:return "Chuẩn Thánh"
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
        case .daiThua:   return Color(red: 0.4, green: 0.9, blue: 0.5)
        case .doKiep:    return Color(red: 0.55, green: 0.55, blue: 0.95)
        case .diaTien:   return Color(red: 0.3, green: 0.9, blue: 0.95)
        case .thienTien: return Color(red: 0.85, green: 0.75, blue: 1.0)
        case .kimTien:   return Color(red: 1.0, green: 0.8, blue: 0.35)
        case .daiLa:     return Color(red: 1.0, green: 0.6, blue: 0.8)
        case .chuanThanh:return Color(red: 0.7, green: 0.95, blue: 1.0)
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

// MARK: - Thú cưng đồng hành (linh thú)
struct TNPet: Identifiable {
    let id: String; let name: String; let emoji: String; let price: Int
    let atk: Int; let def: Int; let hp: Int; let assist: Double   // % công người chơi mỗi lượt
    let desc: String; let color: Color
}
let TN_PETS: [TNPet] = [
    TNPet(id: "tieuhuyen", name: "Tiểu Huyền", emoji: "🐱", price: 200, atk: 10, def: 6, hp: 60, assist: 0.10,
          desc: "Linh thú tinh nghịch · cân bằng, dễ nuôi.", color: .cyan),
    TNPet(id: "banghо",    name: "Băng Hổ", emoji: "🐯", price: 600, atk: 15, def: 22, hp: 120, assist: 0.12,
          desc: "Thánh thú băng hàn · phòng thủ vượt trội.", color: .teal),
    TNPet(id: "loiung",    name: "Lôi Ưng", emoji: "🦅", price: 800, atk: 26, def: 8, hp: 80, assist: 0.22,
          desc: "Thánh thú sấm sét · tiếp sức đòn đánh cực mạnh.", color: .yellow),
    TNPet(id: "thanhlong", name: "Thanh Long", emoji: "🐉", price: 1400, atk: 40, def: 20, hp: 180, assist: 0.20,
          desc: "Thánh thú uy nghiêm · công thủ toàn diện.", color: .blue),
    TNPet(id: "hoaphuong", name: "Hỏa Phượng", emoji: "🔥", price: 1800, atk: 48, def: 15, hp: 160, assist: 0.28,
          desc: "Thánh thú lửa thiêng · sát thương tiếp sức bùng nổ.", color: .red),
    TNPet(id: "kimo",      name: "Kim Ô", emoji: "🐦‍🔥", price: 3200, atk: 70, def: 35, hp: 300, assist: 0.30,
          desc: "Thần điểu bất phàm · mạnh nhất, đồng hành tối thượng.", color: .orange),
]
func tnPet(_ id: String) -> TNPet? { TN_PETS.first { $0.id == id } }

// MARK: - Bang hội (guild) — gia nhập nhận buff, cống hiến lên cấp bang
struct TNGuild: Identifiable {
    let id: String; let name: String; let emoji: String
    let atkBuff: Double; let hpBuff: Double   // % cộng thêm chỉ số
    let members: Int; let desc: String; let color: Color
}
let TN_GUILDS: [TNGuild] = [
    TNGuild(id: "thienmon", name: "Thiên Môn Bang", emoji: "🏯", atkBuff: 0.08, hpBuff: 0.05,
            members: 128, desc: "Đại bang chính đạo · công thủ cân bằng, đông đảo cao thủ.", color: .cyan),
    TNGuild(id: "huyetma",  name: "Huyết Ma Giáo", emoji: "🩸", atkBuff: 0.15, hpBuff: 0.0,
            members: 96,  desc: "Ma đạo hung tàn · tăng công kích cực mạnh, không nể ai.", color: .red),
    TNGuild(id: "vandao",   name: "Vạn Đạo Sơn Trang", emoji: "⛩️", atkBuff: 0.05, hpBuff: 0.14,
            members: 152, desc: "Ẩn thế thế gia · phòng ngự và sinh tồn vượt trội.", color: .green),
    TNGuild(id: "lonhoi",   name: "Luân Hồi Điện", emoji: "🕯️", atkBuff: 0.12, hpBuff: 0.12,
            members: 64,  desc: "Bang hội thần bí · buff toàn diện nhưng khó gia nhập.", color: .purple),
]
func tnGuild(_ id: String) -> TNGuild? { TN_GUILDS.first { $0.id == id } }

// MARK: - Thú cưỡi bay (mount) — cưỡi để tăng chỉ số & oai phong
struct TNMount: Identifiable {
    let id: String; let name: String; let emoji: String; let price: Int
    let atk: Int; let def: Int; let hp: Int; let desc: String; let color: Color
}
let TN_MOUNTS: [TNMount] = [
    TNMount(id: "hac", name: "Hắc Vân Điêu", emoji: "🦅", price: 500, atk: 12, def: 8, hp: 80,
            desc: "Chim ưng mây đen · phi hành nhập môn, nhanh nhẹn.", color: .gray),
    TNMount(id: "bach", name: "Bạch Hạc Tiên", emoji: "🕊️", price: 1200, atk: 18, def: 20, hp: 160,
            desc: "Tiên hạc thanh nhã · cưỡi mây đạp gió, khí chất bất phàm.", color: .teal),
    TNMount(id: "phuong", name: "Ngũ Sắc Phượng", emoji: "🦚", price: 2600, atk: 40, def: 28, hp: 260,
            desc: "Phượng hoàng ngũ sắc · thần thú truyền thuyết, uy chấn tứ phương.", color: .pink),
    TNMount(id: "long", name: "Chân Long Ngự Thiên", emoji: "🐲", price: 5200, atk: 70, def: 50, hp: 460,
            desc: "Chân long ngự thiên · thú cưỡi tối thượng, chân long hộ chủ.", color: .yellow),
]
func tnMount(_ id: String) -> TNMount? { TN_MOUNTS.first { $0.id == id } }

// MARK: - Thời trang: Cánh (đeo sau lưng · vừa đẹp vừa buff)
struct TNWing: Identifiable {
    let id: String; let name: String; let emoji: String; let price: Int
    let atk: Int; let hp: Int; let colors: [Color]; let desc: String
}
let TN_WINGS: [TNWing] = [
    TNWing(id: "none", name: "Không đeo", emoji: "🚫", price: 0, atk: 0, hp: 0, colors: [.gray], desc: "Bỏ trang bị cánh."),
    TNWing(id: "thienvu", name: "Thiên Vũ Cánh", emoji: "🕊️", price: 600, atk: 10, hp: 80,
           colors: [.white, .cyan], desc: "Đôi cánh lông vũ trắng thanh khiết, nhẹ tựa mây."),
    TNWing(id: "hoaphuong", name: "Hỏa Phượng Cánh", emoji: "🔥", price: 1500, atk: 26, hp: 140,
           colors: [.orange, .red], desc: "Cánh phượng lửa rực cháy, bay tới đâu thiêu đốt tới đó."),
    TNWing(id: "bangtinh", name: "Băng Tinh Cánh", emoji: "❄️", price: 1500, atk: 18, hp: 220,
           colors: [.cyan, .blue], desc: "Cánh pha lê băng tinh, lạnh lẽo mà kiêu sa."),
    TNWing(id: "hondiep", name: "Hồn Điệp Cánh", emoji: "🦋", price: 2600, atk: 34, hp: 200,
           colors: [.purple, .pink], desc: "Cánh bướm hồn mộng ngũ sắc, huyễn hoặc lòng người."),
    TNWing(id: "cothan", name: "Cổ Thần Long Dực", emoji: "🐉", price: 5000, atk: 60, hp: 400,
           colors: [Color(red:1,green:0.85,blue:0.2), .orange], desc: "Long dực Cổ Thần chí tôn, mở cánh che kín trời."),
]
func tnWing(_ id: String) -> TNWing? { TN_WINGS.first { $0.id == id && $0.id != "none" } }

// MARK: - Thời trang: Hào quang (vòng sáng quanh thân)
struct TNHalo: Identifiable {
    let id: String; let name: String; let emoji: String; let price: Int
    let atk: Int; let def: Int; let color: Color; let desc: String
}
let TN_HALOS: [TNHalo] = [
    TNHalo(id: "none", name: "Không khoác", emoji: "🚫", price: 0, atk: 0, def: 0, color: .gray, desc: "Bỏ hào quang."),
    TNHalo(id: "thanhloi", name: "Thanh Loi Quang", emoji: "⚡", price: 500, atk: 12, def: 6,
           color: .yellow, desc: "Vòng sáng sấm sét lam, lôi quang chớp giật."),
    TNHalo(id: "tuha", name: "Tử Hà Quang", emoji: "🟣", price: 1200, atk: 18, def: 14,
           color: .purple, desc: "Hào quang tử hà tím huyền, cao quý phi phàm."),
    TNHalo(id: "kimo", name: "Kim Ô Thánh Quang", emoji: "☀️", price: 2400, atk: 32, def: 20,
           color: .orange, desc: "Thánh quang Kim Ô chói lọi như mặt trời."),
    TNHalo(id: "luanhoi", name: "Luân Hồi Thần Quang", emoji: "🌀", price: 4200, atk: 46, def: 34,
           color: .cyan, desc: "Thần quang luân hồi xoay chuyển càn khôn, uy áp tứ phương."),
]
func tnHalo(_ id: String) -> TNHalo? { TN_HALOS.first { $0.id == id && $0.id != "none" } }

// MARK: - Đạo lữ (bạn đời tu tiên) — kết duyên nhận thân mật & buff
struct TNSpouse: Identifiable {
    let id: String; let name: String; let emoji: String; let dowry: Int
    let title: String; let desc: String; let color: Color
}
let TN_SPOUSES: [TNSpouse] = [
    TNSpouse(id: "lymuwan", name: "Lý Mộ Uyển", emoji: "🌸", dowry: 800,
             title: "Thiên Kiều Thánh Nữ", desc: "Tiểu thư danh môn dịu dàng, thanh mai trúc mã của Vương Lâm.", color: .pink),
    TNSpouse(id: "cothanhy", name: "Cổ Thanh Y", emoji: "❄️", dowry: 1600,
             title: "Băng Sơn Kiếm Tiên", desc: "Nữ kiếm tu lạnh lùng, chỉ vì một người mà tan băng.", color: .cyan),
    TNSpouse(id: "hongnhi", name: "Hồng Nhi", emoji: "🔥", dowry: 2400,
             title: "Hỏa Linh Yêu Cơ", desc: "Yêu nữ hoả linh nhiệt tình, ái mộ cường giả nghịch thiên.", color: .red),
    TNSpouse(id: "tuyennguyet", name: "Tuyến Nguyệt Tiên Tử", emoji: "🌙", dowry: 4000,
             title: "Nguyệt Cung Thượng Tiên", desc: "Thượng tiên nơi nguyệt cung, duyên phận vượt tam giới.", color: .purple),
]
func tnSpouse(_ id: String) -> TNSpouse? { TN_SPOUSES.first { $0.id == id } }

// MARK: - Nhiệm vụ hằng ngày (làm mới mỗi ngày, hoàn thành nhận thưởng + chuỗi streak)
struct TNDaily: Identifiable {
    let id: String; let name: String; let emoji: String
    let target: Int; let rewardLT: Int; let rewardExp: Int; let hint: String
}
let TN_DAILIES: [TNDaily] = [
    TNDaily(id: "login", name: "Điểm Danh Nhập Đạo", emoji: "📅", target: 1, rewardLT: 50, rewardExp: 40,
            hint: "Mở game mỗi ngày để điểm danh."),
    TNDaily(id: "medi", name: "Bế Quan Thiền Định", emoji: "🧘", target: 5, rewardLT: 60, rewardExp: 60,
            hint: "Thiền định 5 lần ở màn Tu Luyện."),
    TNDaily(id: "hunt", name: "Trảm Yêu Diệt Ma", emoji: "⚔️", target: 3, rewardLT: 120, rewardExp: 100,
            hint: "Thắng 3 trận chiến đấu bất kỳ."),
    TNDaily(id: "quest", name: "Hành Hiệp Trượng Nghĩa", emoji: "📜", target: 4, rewardLT: 90, rewardExp: 80,
            hint: "Làm 4 nhiệm vụ thường."),
    TNDaily(id: "pvp", name: "Luận Kiếm Đài", emoji: "🏆", target: 1, rewardLT: 100, rewardExp: 90,
            hint: "Giao đấu PvP xếp hạng 1 lần."),
]

// MARK: - Cửa hàng nạp Linh Thạch (gói nạp trong game)
struct TNRecharge: Identifiable {
    let id: String; let name: String; let emoji: String
    let price: String; let linhThach: Int; let bonus: Int; let tag: String; let color: Color
}
let TN_RECHARGES: [TNRecharge] = [
    TNRecharge(id: "p1", name: "Gói Khởi Đầu", emoji: "💠", price: "20.000đ", linhThach: 500, bonus: 0, tag: "", color: .cyan),
    TNRecharge(id: "p2", name: "Gói Tu Sĩ", emoji: "💎", price: "50.000đ", linhThach: 1300, bonus: 130, tag: "+10%", color: .blue),
    TNRecharge(id: "p3", name: "Gói Chân Nhân", emoji: "🔷", price: "100.000đ", linhThach: 2800, bonus: 560, tag: "HOT +20%", color: .indigo),
    TNRecharge(id: "p4", name: "Gói Đại Năng", emoji: "🟣", price: "200.000đ", linhThach: 6000, bonus: 1800, tag: "+30%", color: .purple),
    TNRecharge(id: "p5", name: "Gói Chí Tôn", emoji: "👑", price: "500.000đ", linhThach: 16000, bonus: 6400, tag: "ĐỈNH +40%", color: .orange),
]

// MARK: - VIP đặc quyền (bậc 0–6, mốc theo tổng nạp linh thạch)
struct TNVipTier: Identifiable {
    let id: Int; let name: String; let need: Int; let color: Color; let perks: [String]
}
let TN_VIP_TIERS: [TNVipTier] = [
    TNVipTier(id: 0, name: "Phàm Nhân", need: 0, color: .gray,
              perks: ["Chưa có đặc quyền — nạp linh thạch để mở khoá VIP."]),
    TNVipTier(id: 1, name: "VIP 1 · Nhập Môn", need: 5000, color: .green,
              perks: ["⚔️ +18 công · ❤️ +100 máu", "🎁 Quà ngày +20 linh thạch", "🎊 Mở rương đặc quyền VIP mỗi ngày", "💰 +5% linh thạch & EXP mọi trận"]),
    TNVipTier(id: 2, name: "VIP 2 · Tu Sĩ", need: 10000, color: .cyan,
              perks: ["⚔️ +36 công · ❤️ +200 máu", "🎁 Quà ngày +40 linh thạch", "💰 +10% linh thạch & EXP", "🎊 Rương VIP hạng 2"]),
    TNVipTier(id: 3, name: "VIP 3 · Chân Nhân", need: 15000, color: .blue,
              perks: ["⚔️ +54 công · ❤️ +300 máu", "💰 +15% linh thạch & EXP", "🎊 Rương VIP hạng 3", "👑 Danh hiệu VIP hiện ở màn chính"]),
    TNVipTier(id: 4, name: "VIP 4 · Đại Năng", need: 20000, color: .indigo,
              perks: ["⚔️ +72 công · ❤️ +400 máu", "💰 +20% linh thạch & EXP", "🎊 Rương VIP hạng 4"]),
    TNVipTier(id: 5, name: "VIP 5 · Tôn Giả", need: 25000, color: .purple,
              perks: ["⚔️ +90 công · ❤️ +500 máu", "💰 +25% linh thạch & EXP", "🎊 Rương VIP hạng 5"]),
    TNVipTier(id: 6, name: "VIP 6 · Chí Tôn", need: 30000, color: .orange,
              perks: ["⚔️ +108 công · ❤️ +600 máu", "💰 +30% linh thạch & EXP", "🎊 Rương VIP đỉnh cấp", "🌟 Đặc quyền tối thượng"]),
]

// MARK: - Bậc danh vọng PvP (theo điểm)
struct TNRank { let name: String; let emoji: String; let color: Color }
func tnPvpRank(_ pts: Int) -> TNRank {
    switch pts {
    case ..<100:    return TNRank(name: "Luyện Khí Sĩ", emoji: "🥉", color: .brown)
    case 100..<300: return TNRank(name: "Đấu Giả", emoji: "🥈", color: .gray)
    case 300..<600: return TNRank(name: "Chiến Tướng", emoji: "🥇", color: .yellow)
    case 600..<1000: return TNRank(name: "Đại Năng", emoji: "💠", color: .cyan)
    case 1000..<1600: return TNRank(name: "Tôn Giả", emoji: "👑", color: .orange)
    default:        return TNRank(name: "Chí Tôn Thiên Hạ", emoji: "🔱", color: .red)
    }
}

// MARK: - Bản đồ vùng (khám phá theo cảnh giới)
struct TNZone: Identifiable {
    let id = UUID(); let name: String; let emoji: String; let minRealm: Int
    let foes: [(String, String)]; let rewardMul: Double; let desc: String
}
let TN_ZONES: [TNZone] = [
    TNZone(name: "Thanh Vân Sơn", emoji: "⛰️", minRealm: 0,
           foes: [("Yêu Lang", "🐺"), ("Sơn Trư", "🐗"), ("Độc Xà", "🐍")], rewardMul: 1.0,
           desc: "Ngọn núi khởi đầu của mọi tán tu."),
    TNZone(name: "Hắc Phong Lâm", emoji: "🌲", minRealm: 1,
           foes: [("Hắc Điêu", "🦅"), ("Ma Lang", "🐺"), ("U Hồn", "👻")], rewardMul: 1.25,
           desc: "Rừng gió đen âm u, yêu thú ẩn nấp."),
    TNZone(name: "Xích Diễm Cốc", emoji: "🌋", minRealm: 3,
           foes: [("Hỏa Phượng", "🔥"), ("Diễm Hổ", "🐯"), ("Nham Quái", "🗿")], rewardMul: 1.6,
           desc: "Sơn cốc dung nham, hỏa khí ngút trời."),
    TNZone(name: "Vạn Băng Nguyên", emoji: "🏔️", minRealm: 5,
           foes: [("Băng Hổ", "🐯"), ("Tuyết Yêu", "❄️"), ("Huyền Vũ", "🐢")], rewardMul: 2.0,
           desc: "Băng nguyên vạn dặm, lạnh thấu xương."),
    TNZone(name: "Cửu U Minh Hải", emoji: "🌊", minRealm: 7,
           foes: [("Ma Xà", "🐍"), ("Âm Long", "🐉"), ("Quỷ Vương", "😈")], rewardMul: 2.6,
           desc: "Biển u minh sâu thẳm, tử khí nồng đậm."),
    TNZone(name: "Thiên Ngoại Hư Không", emoji: "🌌", minRealm: 10,
           foes: [("Hư Không Thú", "🌀"), ("Tinh Ma", "⭐"), ("Cổ Yêu", "👁️")], rewardMul: 3.5,
           desc: "Hư không ngoài trời, nơi Cổ Thần trú ngụ."),
]

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
    var hpMax: Int { Int((Double(120 + tier * 70 + level * 22) * sectHp + Double(danHp + petHpB + mountHpB + spouseHpB + vipHpB + wingHpB)) * guildHpMul) }
    var mpMax: Int { 60 + tier * 40 + level * 6 }
    var atk: Int { Int((Double(18 + tier * 12 + level * 4) * sectAtk + Double(weaponLv * 15 + danAtk + petAtkB + mountAtkB + spouseAtkB + vipAtkB + wingAtkB + haloAtkB)) * guildAtkMul) }
    var def: Int { Int(Double(4 + tier * 4 + level) * sectDef) + armorLv * 8 + petDefB + mountDefB + haloDefB }
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
        logDaily("medi")
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
        // Đặc quyền VIP: cộng thêm % linh thạch & EXP
        let lt = Int(Double(linhThach) * vipRewardMul)
        let xp = Int(Double(exp) * vipRewardMul)
        s.linhThach += lt
        s.exp = min(s.exp + xp, s.expMax)
        gainLevelExp(xp)             // đánh quái cũng lên CẤP
        s.linhThao += Int.random(in: 1...3)      // rơi nguyên liệu luyện đan
        s.khoangThach += Int.random(in: 1...3)   // rơi nguyên liệu luyện khí
        logDaily("hunt")             // thắng trận → tiến độ nhiệm vụ ngày
        save()
    }
    // Luyện khí: nâng cấp vũ khí/giáp
    func forge(weapon: Bool) -> String {
        let lv = weapon ? s.weaponLv : s.armorLv
        let costLT = (lv + 1) * 120
        let costMat = (lv + 1) * 3
        guard s.linhThach >= costLT else { return "❌ Thiếu linh thạch (cần \(costLT))." }
        guard s.khoangThach >= costMat else { return "❌ Thiếu khoáng thạch (cần \(costMat))." }
        s.linhThach -= costLT; s.khoangThach -= costMat
        if weapon { s.weaponLv += 1 } else { s.armorLv += 1 }
        save()
        return weapon ? "🗡️ Vũ khí → \(s.weaponName) (+công)!" : "🛡️ Giáp → \(s.armorName) (+thủ)!"
    }
    // Luyện đan: tạo đan dược tăng chỉ số vĩnh viễn
    func alchemy(_ kind: String) -> String {
        let costMat = 5, costLT = 200
        guard s.linhThao >= costMat else { return "❌ Thiếu linh thảo (cần \(costMat))." }
        guard s.linhThach >= costLT else { return "❌ Thiếu linh thạch (cần \(costLT))." }
        s.linhThao -= costMat; s.linhThach -= costLT
        if kind == "atk" { s.danAtk += 8; save(); return "⚔️ Luyện thành Công Kích Đan — Công +8 vĩnh viễn!" }
        else { s.danHp += 40; save(); return "❤️ Luyện thành Bổ Huyết Đan — Máu +40 vĩnh viễn!" }
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

    // Thú cưng: mua & trang bị
    func buyPet(_ p: TNPet) -> Bool {
        guard !s.ownedPets.contains(p.id), s.linhThach >= p.price else { return false }
        s.linhThach -= p.price
        s.ownedPets.append(p.id)
        s.activePet = p.id
        s.hp = min(s.hp, s.hpMax)
        save(); return true
    }
    func equipPet(_ id: String) {
        if id.isEmpty || s.ownedPets.contains(id) { s.activePet = id; s.hp = min(s.hp, s.hpMax); save() }
    }

    // Bang hội: gia nhập / rời / cống hiến
    func joinGuild(_ g: TNGuild) {
        s.guild = g.id
        s.hp = min(s.hp, s.hpMax)   // buff HP đổi max → giữ hợp lệ
        save()
    }
    func leaveGuild() { s.guild = ""; s.guildContrib = 0; s.hp = min(s.hp, s.hpMax); save() }
    func contributeGuild() -> String {
        let cost = 100
        guard s.linhThach >= cost else { return "❌ Thiếu linh thạch (cần \(cost))." }
        s.linhThach -= cost
        s.guildContrib += 10
        save()
        return "🎖️ Cống hiến +10! Tổng cống hiến: \(s.guildContrib)."
    }

    // PvP xếp hạng: đấu đối thủ mô phỏng theo lực chiến, thắng/thua cộng-trừ điểm
    func pvpFight() -> (win: Bool, msg: String) {
        logDaily("pvp")             // tham gia PvP → tiến độ nhiệm vụ ngày
        // Lực chiến người chơi
        let myPower = Double(s.atk) * 2 + Double(s.hpMax) + Double(s.def) * 3
        // Đối thủ mạnh dần theo điểm danh vọng hiện tại
        let foePower = myPower * Double.random(in: 0.8...1.25) * (1 + Double(s.pvpPoints) / 4000)
        let win = myPower >= foePower
        if win {
            let gain = Int.random(in: 18...30)
            s.pvpPoints += gain
            s.pvpWins += 1
            s.linhThach += 60
            save()
            return (true, "🏆 THẮNG! +\(gain) điểm danh vọng · +60 linh thạch.")
        } else {
            let loss = min(s.pvpPoints, Int.random(in: 8...16))
            s.pvpPoints -= loss
            s.pvpLosses += 1
            save()
            return (false, "💥 Thua trận · -\(loss) điểm. Rèn luyện thêm rồi tái chiến!")
        }
    }

    // Thú cưỡi bay: mua & cưỡi
    func buyMount(_ m: TNMount) -> Bool {
        guard !s.ownedMounts.contains(m.id), s.linhThach >= m.price else { return false }
        s.linhThach -= m.price
        s.ownedMounts.append(m.id)
        s.activeMount = m.id
        s.hp = min(s.hp, s.hpMax)
        save(); return true
    }
    func rideMount(_ id: String) {
        if id.isEmpty || s.ownedMounts.contains(id) { s.activeMount = id; s.hp = min(s.hp, s.hpMax); save() }
    }

    // Thời trang cánh: mua & đeo
    func buyWing(_ w: TNWing) -> Bool {
        guard !s.ownedWings.contains(w.id), s.linhThach >= w.price else { return false }
        s.linhThach -= w.price
        s.ownedWings.append(w.id)
        s.activeWing = w.id
        s.hp = min(s.hp, s.hpMax)
        save(); return true
    }
    func equipWing(_ id: String) {
        if id.isEmpty || s.ownedWings.contains(id) { s.activeWing = id; s.hp = min(s.hp, s.hpMax); save() }
    }
    // Hào quang: mua & khoác
    func buyHalo(_ h: TNHalo) -> Bool {
        guard !s.ownedHalos.contains(h.id), s.linhThach >= h.price else { return false }
        s.linhThach -= h.price
        s.ownedHalos.append(h.id)
        s.activeHalo = h.id
        s.hp = min(s.hp, s.hpMax)
        save(); return true
    }
    func equipHalo(_ id: String) {
        if id.isEmpty || s.ownedHalos.contains(id) { s.activeHalo = id; s.hp = min(s.hp, s.hpMax); save() }
    }

    // Đạo lữ: kết duyên (trả sính lễ) & tặng quà tăng thân mật
    func marry(_ sp: TNSpouse) -> String {
        guard s.spouse != sp.id else { return "💞 Hai người đã là đạo lữ rồi." }
        guard s.linhThach >= sp.dowry else { return "❌ Thiếu linh thạch làm sính lễ (cần \(sp.dowry))." }
        s.linhThach -= sp.dowry
        s.spouse = sp.id
        s.affinity = max(s.affinity, 50)
        s.hp = min(s.hp, s.hpMax)
        save()
        return "💐 Kết duyên đạo lữ cùng \(sp.name)! Tình thâm cộng thêm chỉ số."
    }
    func giftSpouse() -> String {
        guard !s.spouse.isEmpty else { return "❌ Chưa có đạo lữ." }
        let cost = 150
        guard s.linhThach >= cost else { return "❌ Thiếu linh thạch tặng quà (cần \(cost))." }
        s.linhThach -= cost
        let old = s.affinityTier
        s.affinity += 40
        s.hp = min(s.hp, s.hpMax)
        save()
        let up = s.affinityTier > old ? " · 💖 Thân mật lên bậc \(s.affinityTier)!" : ""
        return "🎁 Tặng quà — thân mật +40 (hiện \(s.affinity))\(up)"
    }
    func divorce() { s.spouse = ""; s.affinity = 0; s.hp = min(s.hp, s.hpMax); save() }

    // ===== Nhiệm vụ hằng ngày =====
    static let dailyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "vi_VN"); return f
    }()
    private func todayStr() -> String { TNGame.dailyFmt.string(from: Date()) }
    // Sang ngày mới → reset tiến độ & đã lĩnh; điểm danh tự động.
    func rolloverDaily() {
        let today = todayStr()
        if s.dailyDate != today {
            s.dailyDate = today
            s.dailyProg = [:]
            s.dailyClaimed = []
            s.dailyProg["login"] = 1        // mở game = điểm danh
            save()
        }
    }
    // Ghi nhận tiến độ khi người chơi hành động (thiền/đánh/nhiệm vụ/pvp).
    func logDaily(_ key: String, _ n: Int = 1) {
        rolloverDaily()
        s.dailyProg[key, default: 0] += n
        save()
    }
    func dailyDone(_ d: TNDaily) -> Bool { (s.dailyProg[d.id] ?? 0) >= d.target }
    @discardableResult
    func claimDaily(_ d: TNDaily) -> String {
        rolloverDaily()
        guard !s.dailyClaimed.contains(d.id) else { return "Đã lĩnh thưởng rồi." }
        guard dailyDone(d) else { return "❌ Chưa đạt yêu cầu." }
        s.dailyClaimed.append(d.id)
        s.linhThach += d.rewardLT
        gainLevelExp(d.rewardExp)
        var extra = ""
        // Hoàn thành TẤT CẢ nhiệm vụ ngày → cộng chuỗi streak + rương thưởng (1 lần/ngày)
        if TN_DAILIES.allSatisfy({ s.dailyClaimed.contains($0.id) }) && s.lastStreakDate != s.dailyDate {
            s.lastStreakDate = s.dailyDate
            s.dailyStreak += 1
            let chest = 200 + s.dailyStreak * 20
            s.linhThach += chest
            extra = " · 🎊 Trọn ngày! Chuỗi \(s.dailyStreak) ngày — rương thưởng +\(chest) linh thạch!"
        }
        save()
        return "🎁 +\(d.rewardLT) linh thạch · +\(d.rewardExp) EXP\(extra)"
    }

    // ===== Cửa hàng nạp Linh Thạch =====
    var freeGiftReady: Bool { s.lastFreeGift != todayStr() }
    var vipLevel: Int { s.vip }                              // mốc VIP theo tổng nạp
    var vipRewardMul: Double { 1 + Double(s.vip) * 0.05 }    // đặc quyền: +5% thưởng mỗi bậc
    @discardableResult
    func claimFreeGift() -> String {
        guard freeGiftReady else { return "Hôm nay đã nhận quà rồi, mai quay lại nhé." }
        s.lastFreeGift = todayStr()
        let amount = 100 + vipLevel * 20
        s.linhThach += amount
        save()
        return "🎉 Nhận quà miễn phí: +\(amount) linh thạch!"
    }
    // ===== VIP đặc quyền =====
    var vipGiftReady: Bool { s.vip >= 1 && s.lastVipGift != todayStr() }
    @discardableResult
    func claimVipGift() -> String {
        guard s.vip >= 1 else { return "❌ Cần đạt VIP 1 (nạp 5.000 linh thạch tích luỹ)." }
        guard vipGiftReady else { return "Hôm nay đã mở rương VIP rồi, mai quay lại." }
        s.lastVipGift = todayStr()
        let lt = s.vip * 150
        let mat = s.vip * 2
        s.linhThach += lt
        s.linhThao += mat
        s.khoangThach += mat
        save()
        return "🎊 Rương đặc quyền VIP \(s.vip): +\(lt) linh thạch · +\(mat) 🌿 · +\(mat) ⛏️!"
    }
    func recharge(_ pkg: TNRecharge) -> String {
        let total = pkg.linhThach + pkg.bonus
        s.linhThach += total
        s.totalRecharged += total
        s.hp = min(s.hp, s.hpMax)
        save()
        let vip = pkg.bonus > 0 ? " (gồm +\(pkg.bonus) thưởng)" : ""
        return "✅ Nạp thành công +\(total) linh thạch\(vip)! VIP \(vipLevel)"
    }

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
    var wing: TNWing? = nil
    var halo: TNHalo? = nil
    @State private var pulse = false
    @State private var flap = false
    var body: some View {
        ZStack {
            // CÁNH thời trang (sau lưng) — hai bên vỗ nhẹ
            if let w = wing {
                HStack(spacing: size * 0.62) {
                    Text(w.emoji).scaleEffect(x: -1, y: 1)
                    Text(w.emoji)
                }
                .font(.system(size: size * 0.62))
                .shadow(color: w.colors.first!.opacity(0.9), radius: 10)
                .rotationEffect(.degrees(flap ? -6 : 6))
                .offset(y: -size * 0.05)
            }
            // Hào quang xoay + nhấp nháy
            Circle()
                .fill(RadialGradient(colors: [skin.colors.first!.opacity(0.9), realm.color.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .blur(radius: 6)
            // HÀO QUANG thời trang (vòng sáng bổ sung)
            if let h = halo {
                Circle()
                    .strokeBorder(AngularGradient(colors: [h.color, .white, h.color, .clear, h.color], center: .center), lineWidth: 5)
                    .frame(width: size * 1.35, height: size * 1.35)
                    .rotationEffect(.degrees(pulse ? -360 : 0))
                    .shadow(color: h.color, radius: 12)
            }
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
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { flap = true }
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
    @State private var showForge = false
    @State private var showMap = false
    @State private var showPets = false
    @State private var showGuild = false
    @State private var showPvP = false
    @State private var showMount = false
    @State private var showSpouse = false
    @State private var showRecharge = false
    @State private var showVip = false
    @State private var showFashion = false

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

                TNHeroAvatar(skin: tnSkin(game.s.skin), realm: game.s.realmEnum,
                             wing: tnWing(game.s.activeWing), halo: tnHalo(game.s.activeHalo))
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
                    if game.s.vip >= 1 {
                        Text("👑 VIP \(game.s.vip)").font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.3), in: Capsule())
                            .overlay(Capsule().strokeBorder(.orange, lineWidth: 1))
                    }
                }
                .foregroundStyle(.white)

                // Đạo lữ & thú cưỡi đang gắn (nếu có)
                if !game.s.spouse.isEmpty || !game.s.activeMount.isEmpty {
                    HStack(spacing: 8) {
                        if let sp = tnSpouse(game.s.spouse) {
                            Label("\(sp.emoji) \(sp.name)", systemImage: "heart.fill")
                                .font(.caption2.bold()).foregroundStyle(.pink)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.pink.opacity(0.18), in: Capsule())
                        }
                        if let m = tnMount(game.s.activeMount) {
                            Text("🐲 Cưỡi \(m.emoji) \(m.name)")
                                .font(.caption2.bold()).foregroundStyle(.cyan)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.cyan.opacity(0.18), in: Capsule())
                        }
                    }
                }

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
                    Button { showMap = true } label: { bigBtn("🗺️ Bản Đồ — Khám Phá Vùng Đất", [.green, .teal]) }.buttonStyle(TNPress(glow: .green))
                    Button { showPets = true } label: { bigBtn("🐾 Thú Cưng Đồng Hành", [.orange, .pink]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showFashion = true } label: { bigBtn("👗 Thời Trang — Cánh & Hào Quang", [.purple, .pink]) }.buttonStyle(TNPress(glow: .purple))
                    Button { tab = 1 } label: { bigBtn("📖 Đi Theo Cốt Truyện", [.brown, .orange]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showForge = true } label: { bigBtn("⚒️ Chế Tạo — Luyện Khí · Luyện Đan", [.gray, .brown]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showArena = true } label: { bigBtn("🏆 Đấu Đài — Thách Đấu Cao Thủ", [.yellow, .orange]) }.buttonStyle(TNPress(glow: .yellow))
                    Button { showPvP = true } label: { bigBtn("⚔️ PvP Xếp Hạng — Đấu Danh Vọng", [.red, .pink]) }.buttonStyle(TNPress(glow: .red))
                    Button { showGuild = true } label: { bigBtn("🏯 Bang Hội — Gia Nhập Thế Lực", [.indigo, .cyan]) }.buttonStyle(TNPress(glow: .cyan))
                    Button { showMount = true } label: { bigBtn("🐲 Thú Cưỡi Bay — Ngự Không Phi Hành", [.blue, .indigo]) }.buttonStyle(TNPress(glow: .blue))
                    Button { showSpouse = true } label: { bigBtn("💞 Đạo Lữ — Kết Duyên Tu Tiên", [.pink, .red]) }.buttonStyle(TNPress(glow: .pink))
                    Button { showRecharge = true } label: { bigBtn("💰 Nạp Linh Thạch — Cửa Hàng", [.yellow, .green]) }.buttonStyle(TNPress(glow: .green))
                    Button { showVip = true } label: { bigBtn("👑 VIP Đặc Quyền", [.orange, .yellow]) }.buttonStyle(TNPress(glow: .orange))
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
        .sheet(isPresented: $showForge) { TNForgeView(game: game) }
        .fullScreenCover(isPresented: $showMap) { TNMapView(game: game) }
        .sheet(isPresented: $showPets) { TNPetView(game: game) }
        .sheet(isPresented: $showGuild) { TNGuildView(game: game) }
        .fullScreenCover(isPresented: $showPvP) { TNPvPView(game: game) }
        .sheet(isPresented: $showMount) { TNMountView(game: game) }
        .sheet(isPresented: $showSpouse) { TNSpouseView(game: game) }
        .sheet(isPresented: $showRecharge) { TNRechargeView(game: game) }
        .sheet(isPresented: $showVip) { TNVipView(game: game) }
        .sheet(isPresented: $showFashion) { TNFashionView(game: game) }
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
        // 🐾 Thú cưng tiếp sức: gây thêm sát thương mỗi lượt của người chơi
        if let pet = tnPet(game.s.activePet), enemy.hp > 0 {
            let pd = max(1, Int(Double(game.s.atk) * pet.assist))
            enemy.hp = max(0, enemy.hp - pd)
            log += "  \(pet.emoji) +\(pd)"
        }
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

// MARK: - Bản đồ vùng (khám phá → chiến đấu)
struct TNMapView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var showBattle = false
    @State private var zoneIdx = 0
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.04,green:0.1,blue:0.08), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            VStack(spacing: 0) {
                HStack {
                    Text("🗺️ BẢN ĐỒ").font(.title2.bold()).foregroundStyle(.green)
                    Spacer(); Button("Đóng") { dismiss() }.foregroundStyle(.white)
                }.padding()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(TN_ZONES.indices, id: \.self) { i in
                            let z = TN_ZONES[i]
                            let locked = game.s.realm < z.minRealm
                            Button { if !locked { zoneIdx = i; showBattle = true } } label: {
                                HStack(spacing: 12) {
                                    Text(z.emoji).font(.system(size: 40))
                                        .frame(width: 62, height: 62)
                                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(z.name).font(.headline).foregroundStyle(.white)
                                        Text(z.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                        Text(locked ? "🔒 Cần cảnh giới \(TNRealm(rawValue: z.minRealm)?.name ?? "?")"
                                                    : "⚔️ Yêu thú: \(z.foes.map{$0.1}.joined()) · Thưởng x\(String(format:"%.1f",z.rewardMul))")
                                            .font(.system(size: 10, weight: .bold)).foregroundStyle(locked ? .gray : .green)
                                    }
                                    Spacer()
                                    if !locked { Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5)) }
                                }
                                .padding(12)
                                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                                .opacity(locked ? 0.55 : 1)
                            }
                            .buttonStyle(TNPress(glow: .green)).disabled(locked)
                            .padding(.horizontal)
                        }
                        Color.clear.frame(height: 20)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: zoneEnemy(TN_ZONES[zoneIdx]), storyMode: false, onDone: { _ in })
        }
    }
    private func zoneEnemy(_ z: TNZone) -> TNEnemy {
        let f = z.foes.randomElement()!
        let lvl = Double(game.s.realm * 9 + game.s.stage + game.s.level / 5)
        let hp = Int((90 + lvl * 90) * z.rewardMul)
        return TNEnemy(name: f.0, emoji: f.1, hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * 0.6 * z.rewardMul), def: Int(Double(game.s.def) * 0.6),
                       reward: Int((45 + lvl * 12) * z.rewardMul), exp: Int((35 + lvl * 18) * z.rewardMul))
    }
}

// MARK: - Thú cưng đồng hành
struct TNPetView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🐾 THÚ CƯNG").font(.title2.bold()).foregroundStyle(.orange)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)
                    Text("Thú cưng cộng chỉ số & TIẾP SỨC sát thương mỗi lượt đánh.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    // Bỏ trang bị
                    if !game.s.activePet.isEmpty {
                        Button { game.equipPet("") } label: {
                            Text("Đang đồng hành: \(tnPet(game.s.activePet)?.emoji ?? "") \(tnPet(game.s.activePet)?.name ?? "") — bấm để THU HỒI")
                                .font(.caption).foregroundStyle(.yellow)
                        }
                    }
                    ForEach(TN_PETS) { p in
                        let owned = game.s.ownedPets.contains(p.id)
                        let active = game.s.activePet == p.id
                        HStack(spacing: 12) {
                            Text(p.emoji).font(.system(size: 34))
                                .frame(width: 56, height: 56)
                                .background(p.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline).foregroundStyle(.white)
                                Text(p.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                Text("⚔️+\(p.atk) 🛡️+\(p.def) ❤️+\(p.hp) · 🐾 tiếp sức \(Int(p.assist*100))%")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(p.color)
                            }
                            Spacer()
                            if active { Text("Đồng hành").font(.caption.bold()).foregroundStyle(.green) }
                            else if owned {
                                Button("Chọn") { game.equipPet(p.id) }.font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7).background(.blue, in: Capsule())
                            } else {
                                Button("💎\(p.price)") { flash(game.buyPet(p) ? "✅ Đã thu phục \(p.name)!" : "❌ Không đủ linh thạch!") }
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(game.s.linhThach >= p.price ? Color.orange : Color.gray, in: Capsule())
                                    .buttonStyle(TNPress(glow: .orange))
                            }
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.1,green:0.06,blue:0.08), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thú Cưng").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Chế Tạo (Luyện Khí nâng trang bị · Luyện Đan tăng chỉ số)
struct TNForgeView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Kho nguyên liệu
                    HStack(spacing: 14) {
                        matChip("💎", game.s.linhThach, "Linh thạch")
                        matChip("🌿", game.s.linhThao, "Linh thảo")
                        matChip("⛏️", game.s.khoangThach, "Khoáng thạch")
                    }.padding(.horizontal).padding(.top, 8)
                    Text("Đánh quái / Đấu Đài để rơi thêm linh thảo & khoáng thạch.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))

                    // Luyện Khí
                    section("🗡️ Luyện Khí — Rèn trang bị") {
                        forgeRow("🗡️ \(game.s.weaponName)", "Nâng vũ khí (+15 công/cấp)",
                                 "💎\((game.s.weaponLv+1)*120) · ⛏️\((game.s.weaponLv+1)*3)") { flash(game.forge(weapon: true)) }
                        forgeRow("🛡️ \(game.s.armorName)", "Nâng giáp (+8 thủ/cấp)",
                                 "💎\((game.s.armorLv+1)*120) · ⛏️\((game.s.armorLv+1)*3)") { flash(game.forge(weapon: false)) }
                    }
                    // Luyện Đan
                    section("⚗️ Luyện Đan — Đan dược vĩnh viễn") {
                        forgeRow("⚔️ Công Kích Đan (Công +8)", "Tăng công vĩnh viễn · hiện +\(game.s.danAtk)",
                                 "💎200 · 🌿5") { flash(game.alchemy("atk")) }
                        forgeRow("❤️ Bổ Huyết Đan (Máu +40)", "Tăng máu vĩnh viễn · hiện +\(game.s.danHp)",
                                 "💎200 · 🌿5") { flash(game.alchemy("hp")) }
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.08,green:0.07,blue:0.05), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Chế Tạo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func matChip(_ e: String, _ v: Int, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text("\(e) \(v)").font(.subheadline.bold()).foregroundStyle(.white)
            Text(t).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.yellow)
            content()
        }.padding(.horizontal)
    }
    private func forgeRow(_ name: String, _ desc: String, _ cost: String, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.bold()).foregroundStyle(.white)
                Text(desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text("Giá: \(cost)").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
            }
            Spacer()
            Button("Làm", action: action).font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(.green, in: Capsule()).buttonStyle(TNPress(glow: .green))
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if msg == m { msg = nil } } }
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

// MARK: - Bang Hội (gia nhập thế lực nhận buff · cống hiến)
struct TNGuildView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🏯 BANG HỘI").font(.title2.bold()).foregroundStyle(.cyan)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)

                    if let g = tnGuild(game.s.guild) {
                        // Thẻ bang hiện tại
                        VStack(spacing: 8) {
                            Text("\(g.emoji) \(g.name)").font(.title3.bold()).foregroundStyle(g.color)
                            Text("Buff: ⚔️ +\(Int(g.atkBuff*100))% công · ❤️ +\(Int(g.hpBuff*100))% máu")
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                            Text("🎖️ Cống hiến của bạn: \(game.s.guildContrib)")
                                .font(.subheadline.bold()).foregroundStyle(.yellow)
                            HStack(spacing: 10) {
                                Button { flash(game.contributeGuild()) } label: {
                                    Text("💎 Cống hiến (100)").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .background(.green, in: Capsule())
                                }.buttonStyle(TNPress(glow: .green))
                                Button { game.leaveGuild(); flash("Đã rời bang hội.") } label: {
                                    Text("Rời bang").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .background(.red.opacity(0.8), in: Capsule())
                                }.buttonStyle(TNPress(glow: .red))
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .background(g.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(g.color.opacity(0.6), lineWidth: 1))
                        .padding(.horizontal)
                    } else {
                        Text("Gia nhập một bang hội để nhận buff chỉ số vĩnh viễn khi còn là thành viên.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }

                    ForEach(TN_GUILDS) { g in
                        let joined = game.s.guild == g.id
                        HStack(spacing: 12) {
                            Text(g.emoji).font(.system(size: 34))
                                .frame(width: 56, height: 56)
                                .background(g.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline).foregroundStyle(.white)
                                Text(g.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                Text("⚔️+\(Int(g.atkBuff*100))% ❤️+\(Int(g.hpBuff*100))% · 👥 \(g.members) thành viên")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(g.color)
                            }
                            Spacer()
                            if joined { Text("Đang ở").font(.caption.bold()).foregroundStyle(.green) }
                            else {
                                Button("Gia nhập") { game.joinGuild(g); flash("✅ Đã gia nhập \(g.name)!") }
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(g.color, in: Capsule())
                                    .buttonStyle(TNPress(glow: g.color))
                            }
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.05,green:0.08,blue:0.12), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Bang Hội").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - PvP Xếp Hạng (đấu danh vọng leo bậc)
struct TNPvPView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var fighting = false
    @State private var result: String?
    @State private var resultWin = false
    @State private var shake = false

    var body: some View {
        let rank = tnPvpRank(game.s.pvpPoints)
        ZStack {
            LinearGradient(colors: [Color(red:0.12,green:0.03,blue:0.06), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("⚔️ PvP XẾP HẠNG").font(.title2.bold()).foregroundStyle(.red)
                        Spacer()
                        Button("Đóng") { dismiss() }.foregroundStyle(.white)
                    }.padding(.horizontal).padding(.top, 10)

                    // Bảng danh vọng
                    VStack(spacing: 6) {
                        Text(rank.emoji).font(.system(size: 54))
                        Text(rank.name).font(.title3.bold()).foregroundStyle(rank.color)
                        Text("\(game.s.pvpPoints) điểm danh vọng").font(.headline).foregroundStyle(.white)
                        Text("🏆 Thắng \(game.s.pvpWins) · 💥 Thua \(game.s.pvpLosses)")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(20).frame(maxWidth: .infinity)
                    .background(rank.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(rank.color.opacity(0.6), lineWidth: 1))
                    .padding(.horizontal)
                    .scaleEffect(shake ? 1.03 : 1.0)

                    // Bậc danh vọng
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Các bậc danh vọng").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                        rankRow("🥉 Luyện Khí Sĩ", "0+", .brown)
                        rankRow("🥈 Đấu Giả", "100+", .gray)
                        rankRow("🥇 Chiến Tướng", "300+", .yellow)
                        rankRow("💠 Đại Năng", "600+", .cyan)
                        rankRow("👑 Tôn Giả", "1000+", .orange)
                        rankRow("🔱 Chí Tôn Thiên Hạ", "1600+", .red)
                    }
                    .padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Button {
                        let r = game.pvpFight()
                        resultWin = r.win; result = r.msg
                        TNHaptic.hit(r.win ? .heavy : .light)
                        withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { shake = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shake = false }
                    } label: {
                        Text("⚔️ TÌM ĐỐI THỦ — GIAO ĐẤU!").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing),
                                        in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(TNPress(glow: .red)).padding(.horizontal)
                    .shadow(color: .red.opacity(0.5), radius: 8)

                    if let result {
                        Text(result).font(.subheadline.bold())
                            .foregroundStyle(resultWin ? .green : .orange)
                            .multilineTextAlignment(.center)
                            .padding(12).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Color.clear.frame(height: 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    private func rankRow(_ name: String, _ pts: String, _ c: Color) -> some View {
        HStack {
            Text(name).font(.caption).foregroundStyle(c)
            Spacer()
            Text(pts).font(.caption2.bold()).foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Thú Cưỡi Bay (mua & cưỡi để tăng chỉ số + oai phong)
struct TNMountView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🐲 THÚ CƯỠI BAY").font(.title2.bold()).foregroundStyle(.blue)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)
                    Text("Cưỡi thú bay để tăng chỉ số & ngự không phi hành khắp tiên giới.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                    if !game.s.activeMount.isEmpty {
                        Button { game.rideMount("") } label: {
                            Text("Đang cưỡi: \(tnMount(game.s.activeMount)?.emoji ?? "") \(tnMount(game.s.activeMount)?.name ?? "") — bấm để XUỐNG")
                                .font(.caption).foregroundStyle(.yellow)
                        }
                    }
                    ForEach(TN_MOUNTS) { m in
                        let owned = game.s.ownedMounts.contains(m.id)
                        let active = game.s.activeMount == m.id
                        HStack(spacing: 12) {
                            Text(m.emoji).font(.system(size: 34))
                                .frame(width: 56, height: 56)
                                .background(m.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.headline).foregroundStyle(.white)
                                Text(m.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                Text("⚔️+\(m.atk) 🛡️+\(m.def) ❤️+\(m.hp)")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(m.color)
                            }
                            Spacer()
                            if active { Text("Đang cưỡi").font(.caption.bold()).foregroundStyle(.green) }
                            else if owned {
                                Button("Cưỡi") { game.rideMount(m.id) }.font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7).background(.blue, in: Capsule())
                            } else {
                                Button("💎\(m.price)") { flash(game.buyMount(m) ? "✅ Đã thu phục \(m.name)!" : "❌ Không đủ linh thạch!") }
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(game.s.linhThach >= m.price ? Color.orange : Color.gray, in: Capsule())
                                    .buttonStyle(TNPress(glow: .orange))
                            }
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.04,green:0.06,blue:0.14), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thú Cưỡi").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Đạo Lữ (kết duyên tu tiên · tặng quà tăng thân mật)
struct TNSpouseView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    @State private var hearts = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("💞 ĐẠO LỮ").font(.title2.bold()).foregroundStyle(.pink)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)

                    if let sp = tnSpouse(game.s.spouse) {
                        VStack(spacing: 8) {
                            Text(sp.emoji).font(.system(size: 56)).scaleEffect(hearts ? 1.12 : 1.0)
                            Text("💐 \(sp.name)").font(.title3.bold()).foregroundStyle(sp.color)
                            Text(sp.title).font(.caption).foregroundStyle(.white.opacity(0.75))
                            Text("💖 Thân mật: \(game.s.affinity) · Bậc \(game.s.affinityTier)/5")
                                .font(.subheadline.bold()).foregroundStyle(.pink)
                            Text("Buff đạo lữ: ⚔️ +\(game.s.affinityTier*12) công · ❤️ +\(game.s.affinityTier*60) máu")
                                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            HStack(spacing: 10) {
                                Button {
                                    flash(game.giftSpouse())
                                    withAnimation(.spring()) { hearts = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hearts = false }
                                } label: {
                                    Text("🎁 Tặng quà (150)").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .background(.pink, in: Capsule())
                                }.buttonStyle(TNPress(glow: .pink))
                                Button { game.divorce(); flash("Đã hoà li, duyên phận đã hết.") } label: {
                                    Text("Hoà li").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .background(.gray.opacity(0.7), in: Capsule())
                                }.buttonStyle(TNPress(glow: .gray))
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .background(sp.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(sp.color.opacity(0.6), lineWidth: 1))
                        .padding(.horizontal)
                    } else {
                        Text("Kết duyên đạo lữ để đồng tu song hành — tình thâm càng sâu, chỉ số càng mạnh.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }

                    Text(game.s.spouse.isEmpty ? "Chọn đạo lữ để kết duyên" : "Đổi đạo lữ (kết duyên lại)")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                    ForEach(TN_SPOUSES) { sp in
                        let cur = game.s.spouse == sp.id
                        HStack(spacing: 12) {
                            Text(sp.emoji).font(.system(size: 34))
                                .frame(width: 56, height: 56)
                                .background(sp.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sp.name).font(.headline).foregroundStyle(.white)
                                Text(sp.title).font(.caption2.bold()).foregroundStyle(sp.color)
                                Text(sp.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            if cur { Text("Đạo lữ").font(.caption.bold()).foregroundStyle(.green) }
                            else {
                                Button("💍 \(sp.dowry)") { flash(game.marry(sp)) }
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(game.s.linhThach >= sp.dowry ? sp.color : Color.gray, in: Capsule())
                                    .buttonStyle(TNPress(glow: sp.color))
                            }
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.12,green:0.04,blue:0.09), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Đạo Lữ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Cửa hàng nạp Linh Thạch (quà miễn phí + gói nạp)
struct TNRechargeView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    @State private var pending: TNRecharge?      // gói đang chờ xác nhận nạp
    @State private var shine = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Số dư + VIP
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("💎 \(game.s.linhThach)").font(.title3.bold()).foregroundStyle(.cyan)
                            Text("Số dư linh thạch").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("👑 VIP \(game.vipLevel)").font(.headline.bold()).foregroundStyle(.orange)
                            Text("Tổng nạp \(game.s.totalRecharged)").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal).padding(.top, 8)

                    // Quà miễn phí mỗi ngày
                    Button {
                        msg = game.claimFreeGift(); TNHaptic.success()
                    } label: {
                        HStack {
                            Text("🎁").font(.system(size: 30))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quà Miễn Phí Mỗi Ngày").font(.subheadline.bold()).foregroundStyle(.white)
                                Text(game.freeGiftReady ? "Nhận ngay +\(100 + game.vipLevel*20) linh thạch!" : "Đã nhận hôm nay · mai quay lại")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Text(game.freeGiftReady ? "NHẬN" : "✓")
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(game.freeGiftReady ? Color.green : Color.gray, in: Capsule())
                        }
                        .padding(12)
                        .background(LinearGradient(colors: [.green.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.green.opacity(0.4), lineWidth: 1))
                    }
                    .disabled(!game.freeGiftReady)
                    .buttonStyle(TNPress(glow: .green)).padding(.horizontal)

                    Text("🛒 GÓI NẠP LINH THẠCH").font(.subheadline.bold()).foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)

                    ForEach(TN_RECHARGES) { pkg in
                        Button { pending = pkg } label: {
                            HStack(spacing: 12) {
                                Text(pkg.emoji).font(.system(size: 34))
                                    .frame(width: 56, height: 56)
                                    .background(pkg.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(pkg.name).font(.headline).foregroundStyle(.white)
                                        if !pkg.tag.isEmpty {
                                            Text(pkg.tag).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.red, in: Capsule())
                                        }
                                    }
                                    Text("💎 \(pkg.linhThach)\(pkg.bonus > 0 ? " + \(pkg.bonus) thưởng" : "")")
                                        .font(.caption.bold()).foregroundStyle(pkg.color)
                                }
                                Spacer()
                                Text(pkg.price).font(.subheadline.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(LinearGradient(colors: [pkg.color, pkg.color.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: Capsule())
                            }
                            .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(TNPress(glow: pkg.color)).padding(.horizontal)
                    }

                    Text("Cửa hàng nạp trong game — linh thạch dùng để mua skin, thú cưng, thú cưỡi, đạo lữ, rèn trang bị…")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center).padding(.horizontal)

                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.08,green:0.1,blue:0.05), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Nạp Linh Thạch").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
            .alert("Xác nhận nạp", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Nạp \(pending?.price ?? "")") {
                    if let p = pending { msg = game.recharge(p); TNHaptic.success() }
                    pending = nil
                }
                Button("Huỷ", role: .cancel) { pending = nil }
            } message: {
                Text("Nạp gói \(pending?.name ?? "") — nhận \(( (pending?.linhThach ?? 0) + (pending?.bonus ?? 0) )) linh thạch.")
            }
        }
    }
}

// MARK: - VIP Đặc Quyền (bậc VIP · rương ngày · quyền lợi)
struct TNVipView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    @State private var glow = false
    private var curTier: TNVipTier { TN_VIP_TIERS[min(game.s.vip, TN_VIP_TIERS.count - 1)] }
    private var nextTier: TNVipTier? { game.s.vip < 6 ? TN_VIP_TIERS[game.s.vip + 1] : nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Huy hiệu VIP hiện tại
                    VStack(spacing: 8) {
                        Text("👑").font(.system(size: 54)).scaleEffect(glow ? 1.1 : 1.0)
                            .shadow(color: curTier.color, radius: glow ? 16 : 6)
                        Text(curTier.name).font(.title2.bold()).foregroundStyle(curTier.color)
                        Text("Tổng nạp tích luỹ: \(game.s.totalRecharged) linh thạch")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                        if let nt = nextTier {
                            let need = max(0, nt.need - game.s.totalRecharged)
                            TNBar(value: game.s.totalRecharged, maxValue: nt.need, colors: [curTier.color, .orange], label: "")
                                .frame(height: 16).padding(.horizontal, 30)
                            Text("Còn \(need) nữa để lên \(nt.name)").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        } else {
                            Text("🌟 Đã đạt VIP tối đa — Chí Tôn!").font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity)
                    .background(curTier.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(curTier.color.opacity(0.6), lineWidth: 1))
                    .padding(.horizontal).onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true } }

                    // Rương đặc quyền VIP mỗi ngày
                    Button {
                        msg = game.claimVipGift(); TNHaptic.success()
                    } label: {
                        HStack {
                            Text("🎊").font(.system(size: 30))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rương Đặc Quyền VIP").font(.subheadline.bold()).foregroundStyle(.white)
                                Text(game.s.vip < 1 ? "Cần VIP 1 để mở khoá"
                                     : (game.vipGiftReady ? "Nhận +\(game.s.vip*150) linh thạch + nguyên liệu!" : "Đã nhận hôm nay · mai quay lại"))
                                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Text(game.vipGiftReady ? "MỞ" : "✓").font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(game.vipGiftReady ? Color.orange : Color.gray, in: Capsule())
                        }
                        .padding(12)
                        .background(LinearGradient(colors: [.orange.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.orange.opacity(0.4), lineWidth: 1))
                    }
                    .disabled(!game.vipGiftReady)
                    .buttonStyle(TNPress(glow: .orange)).padding(.horizontal)

                    // Bảng đặc quyền các bậc
                    Text("📜 BẢNG ĐẶC QUYỀN VIP").font(.subheadline.bold()).foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    ForEach(TN_VIP_TIERS.dropFirst()) { t in
                        let reached = game.s.vip >= t.id
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(t.name).font(.subheadline.bold()).foregroundStyle(reached ? t.color : .white.opacity(0.5))
                                Spacer()
                                Text(reached ? "✅ Đã đạt" : "Nạp \(t.need)")
                                    .font(.caption2.bold()).foregroundStyle(reached ? .green : .white.opacity(0.5))
                            }
                            ForEach(t.perks, id: \.self) { p in
                                Text("• \(p)").font(.caption2).foregroundStyle(.white.opacity(reached ? 0.85 : 0.5))
                            }
                        }
                        .padding(12)
                        .background((reached ? t.color.opacity(0.12) : Color.white.opacity(0.04)), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(reached ? t.color.opacity(0.5) : .clear, lineWidth: 1))
                        .padding(.horizontal)
                    }

                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.12,green:0.09,blue:0.02), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("VIP Đặc Quyền").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Thời Trang: Cánh & Hào Quang (xem trước trên avatar · mua · trang bị)
struct TNFashionView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0            // 0: cánh · 1: hào quang
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Xem trước avatar với cánh + hào quang đang chọn
                    TNHeroAvatar(skin: tnSkin(game.s.skin), realm: game.s.realmEnum, size: 120,
                                 wing: tnWing(game.s.activeWing), halo: tnHalo(game.s.activeHalo))
                        .frame(height: 190).padding(.top, 10)
                    HStack {
                        Text("👗 THỜI TRANG").font(.title3.bold()).foregroundStyle(.pink)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal)

                    // Chuyển tab cánh / hào quang
                    Picker("", selection: $tab) {
                        Text("🪽 Cánh").tag(0); Text("💫 Hào Quang").tag(1)
                    }.pickerStyle(.segmented).padding(.horizontal)

                    if tab == 0 {
                        ForEach(TN_WINGS) { w in wingRow(w) }
                    } else {
                        ForEach(TN_HALOS) { h in haloRow(h) }
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.1,green:0.04,blue:0.12), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thời Trang").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private func wingRow(_ w: TNWing) -> some View {
        let isNone = w.id == "none"
        let owned = isNone || game.s.ownedWings.contains(w.id)
        let active = game.s.activeWing == w.id || (isNone && game.s.activeWing.isEmpty)
        HStack(spacing: 12) {
            Text(w.emoji).font(.system(size: 32)).frame(width: 54, height: 54)
                .background(w.colors.first!.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(.headline).foregroundStyle(.white)
                Text(w.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                if !isNone { Text("⚔️+\(w.atk) ❤️+\(w.hp)").font(.system(size: 10, weight: .bold)).foregroundStyle(w.colors.first!) }
            }
            Spacer()
            fashionButton(active: active, owned: owned, price: w.price,
                          equip: { game.equipWing(isNone ? "" : w.id) },
                          buy: { flash(game.buyWing(w) ? "✅ Đã sắm \(w.name)!" : "❌ Không đủ linh thạch!") },
                          color: w.colors.first!)
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
    }

    @ViewBuilder private func haloRow(_ h: TNHalo) -> some View {
        let isNone = h.id == "none"
        let owned = isNone || game.s.ownedHalos.contains(h.id)
        let active = game.s.activeHalo == h.id || (isNone && game.s.activeHalo.isEmpty)
        HStack(spacing: 12) {
            Text(h.emoji).font(.system(size: 32)).frame(width: 54, height: 54)
                .background(h.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).font(.headline).foregroundStyle(.white)
                Text(h.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                if !isNone { Text("⚔️+\(h.atk) 🛡️+\(h.def)").font(.system(size: 10, weight: .bold)).foregroundStyle(h.color) }
            }
            Spacer()
            fashionButton(active: active, owned: owned, price: h.price,
                          equip: { game.equipHalo(isNone ? "" : h.id) },
                          buy: { flash(game.buyHalo(h) ? "✅ Đã sắm \(h.name)!" : "❌ Không đủ linh thạch!") },
                          color: h.color)
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
    }

    @ViewBuilder private func fashionButton(active: Bool, owned: Bool, price: Int,
                                            equip: @escaping () -> Void, buy: @escaping () -> Void, color: Color) -> some View {
        if active { Text("Đang dùng").font(.caption.bold()).foregroundStyle(.green) }
        else if owned {
            Button("Dùng") { equip() }.font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7).background(.blue, in: Capsule())
        } else {
            Button("💎\(price)") { buy() }.font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(game.s.linhThach >= price ? color : Color.gray, in: Capsule())
                .buttonStyle(TNPress(glow: color))
        }
    }

    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
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

                // ===== NHIỆM VỤ HẰNG NGÀY =====
                dailySection

                Text("Nhiệm vụ thường — làm để tăng EXP lên cấp (tối đa cấp 100).")
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
        .onAppear { game.rolloverDaily() }
    }

    // Bảng nhiệm vụ hằng ngày (làm mới mỗi ngày · hoàn thành cả bảng nhận rương + streak)
    private var dailySection: some View {
        let allClaimed = TN_DAILIES.allSatisfy { game.s.dailyClaimed.contains($0.id) }
        return VStack(spacing: 10) {
            HStack {
                Text("🗓️ NHIỆM VỤ HẰNG NGÀY").font(.subheadline.bold()).foregroundStyle(.cyan)
                Spacer()
                Text("🔥 Chuỗi \(game.s.dailyStreak) ngày").font(.caption.bold()).foregroundStyle(.orange)
            }
            Text("Làm mới mỗi ngày · hoàn thành cả bảng nhận thêm rương thưởng.")
                .font(.caption2).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(TN_DAILIES) { d in
                let prog = min(game.s.dailyProg[d.id] ?? 0, d.target)
                let done = prog >= d.target
                let claimed = game.s.dailyClaimed.contains(d.id)
                HStack(spacing: 10) {
                    Text(d.emoji).font(.system(size: 26)).frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.name).font(.subheadline.bold()).foregroundStyle(.white)
                        Text(d.hint).font(.caption2).foregroundStyle(.white.opacity(0.55))
                        HStack(spacing: 6) {
                            TNBar(value: prog, maxValue: d.target, colors: [.cyan, .blue], label: "")
                            Text("\(prog)/\(d.target)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        }
                        Text("🎁 +\(d.rewardLT) 💎 · +\(d.rewardExp) EXP").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                    }
                    Button {
                        let r = game.claimDaily(d)
                        flash(r)
                        TNHaptic.success()
                    } label: {
                        Text(claimed ? "✓" : (done ? "Lĩnh" : "🔒"))
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 52).padding(.vertical, 8)
                            .background(claimed ? Color.gray.opacity(0.5) : (done ? Color.green : Color.gray),
                                        in: Capsule())
                    }
                    .disabled(claimed || !done)
                    .buttonStyle(TNPress(glow: .green))
                }
                .padding(10)
                .background((claimed ? Color.green.opacity(0.1) : Color.white.opacity(0.05)), in: RoundedRectangle(cornerRadius: 12))
            }
            if allClaimed {
                Text("🎊 Đã hoàn thành toàn bộ nhiệm vụ hôm nay — hẹn gặp lại ngày mai!")
                    .font(.caption.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center)
            }
        }
        .padding(14).background(.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.cyan.opacity(0.3), lineWidth: 1))
        .padding(.horizontal)
    }

    private func cooldownLeft(_ id: String) -> Int {
        guard let t = cooldowns[id] else { return 0 }
        return max(0, 15 - Int(Date().timeIntervalSince(t)))
    }
    private func doQuest(_ q: (String, String, String, Int, Int, String)) {
        let up = game.gainLevelExp(q.3)
        game.s.linhThach += q.4
        game.logDaily("quest")       // làm nhiệm vụ thường → tiến độ nhiệm vụ ngày
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
