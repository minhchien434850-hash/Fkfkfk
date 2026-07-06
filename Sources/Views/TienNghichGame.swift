import SwiftUI
import UIKit
import AudioToolbox

// Rung phản hồi khi tung chiêu (cho game "đã tay")
enum TNHaptic {
    static func hit(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let g = UIImpactFeedbackGenerator(style: style); g.prepare(); g.impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// Âm thanh game (dùng System Sound của iOS — không cần đóng gói file, chạy offline)
enum TNSound {
    static func play(_ id: SystemSoundID) { AudioServicesPlaySystemSound(id) }
    static func tap()   { play(1104) }   // chạm nút
    static func cast()  { play(1123) }   // tung chiêu
    static func hit()   { play(1520) }   // trúng đòn
    static func win()   { play(1025) }   // thắng trận
    static func level() { play(1027) }   // lên cấp / đột phá
    static func talk()  { play(1103) }   // NPC nói (từng chữ)
    static func coin()  { play(1057) }   // nhận thưởng
}

// Hiệu ứng NHẤN nút: thu nhỏ + phát sáng + PHÁT ÂM THANH khi bấm
struct TNPress: ButtonStyle {
    var glow: Color = .white
    var silent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .shadow(color: glow.opacity(configuration.isPressed ? 0.9 : 0.0), radius: configuration.isPressed ? 12 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed && !silent { TNSound.tap() }
            }
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

// MARK: - Danh hiệu (đeo cạnh tên · cộng uy danh)
struct TNTitle: Identifiable {
    let id: String; let name: String; let color: Color; let atk: Int; let hp: Int
}
let TN_TITLES: [TNTitle] = [
    TNTitle(id: "tanbinh",   name: "Tân Binh Nhập Đạo", color: .gray,   atk: 5,  hp: 30),
    TNTitle(id: "sathu",     name: "Sát Thủ Yêu Ma",    color: .red,    atk: 20, hp: 60),
    TNTitle(id: "chienthan", name: "Bách Chiến Chiến Thần", color: .orange, atk: 45, hp: 150),
    TNTitle(id: "kimdan",    name: "Kim Đan Chân Nhân",  color: .yellow, atk: 25, hp: 120),
    TNTitle(id: "nguyenanh", name: "Nguyên Anh Lão Tổ",  color: .purple, atk: 40, hp: 220),
    TNTitle(id: "dokiep",    name: "Độ Kiếp Cường Giả",  color: .indigo, atk: 70, hp: 400),
    TNTitle(id: "cothan",    name: "Cổ Thần Bất Diệt",   color: Color(red:1,green:0.85,blue:0.2), atk: 120, hp: 800),
    TNTitle(id: "dangphong", name: "Đăng Phong Tạo Cực", color: .mint,   atk: 60, hp: 300),
    TNTitle(id: "kiemvuong", name: "Luận Kiếm Chi Vương", color: .cyan,  atk: 55, hp: 200),
    TNTitle(id: "nguthu",    name: "Ngự Thú Đại Sư",     color: .green,  atk: 30, hp: 180),
    TNTitle(id: "quyenlu",   name: "Thần Tiên Quyến Lữ", color: .pink,   atk: 28, hp: 160),
    TNTitle(id: "haophu",    name: "Hào Phú Nhất Phương", color: .orange, atk: 35, hp: 200),
]
func tnTitle(_ id: String) -> TNTitle? { TN_TITLES.first { $0.id == id } }

// MARK: - Thành tựu (đạt điều kiện → lĩnh thưởng & mở khoá danh hiệu)
struct TNAchievement: Identifiable {
    let id: String; let name: String; let emoji: String; let desc: String
    let rewardLT: Int; let titleId: String; let check: (TNSave) -> Bool
}
let TN_ACHIEVEMENTS: [TNAchievement] = [
    TNAchievement(id: "a_win1",  name: "Khai Sát Giới", emoji: "🗡️", desc: "Thắng trận chiến đầu tiên.",
                  rewardLT: 100, titleId: "tanbinh") { $0.totalWins >= 1 },
    TNAchievement(id: "a_win50", name: "Sát Thủ Thành Danh", emoji: "☠️", desc: "Thắng 50 trận chiến.",
                  rewardLT: 400, titleId: "sathu") { $0.totalWins >= 50 },
    TNAchievement(id: "a_win200", name: "Bách Chiến Bách Thắng", emoji: "⚔️", desc: "Thắng 200 trận chiến.",
                  rewardLT: 1200, titleId: "chienthan") { $0.totalWins >= 200 },
    TNAchievement(id: "a_kimdan", name: "Ngưng Kết Kim Đan", emoji: "🟡", desc: "Đột phá tới cảnh giới Kết Đan.",
                  rewardLT: 300, titleId: "kimdan") { $0.realm >= 2 },
    TNAchievement(id: "a_nguyenanh", name: "Nguyên Anh Xuất Thế", emoji: "👶", desc: "Đột phá tới cảnh giới Nguyên Anh.",
                  rewardLT: 600, titleId: "nguyenanh") { $0.realm >= 3 },
    TNAchievement(id: "a_dokiep", name: "Vượt Thiên Kiếp", emoji: "🌩️", desc: "Đột phá tới cảnh giới Độ Kiếp.",
                  rewardLT: 1500, titleId: "dokiep") { $0.realm >= 8 },
    TNAchievement(id: "a_cothan", name: "Thành Tựu Cổ Thần", emoji: "🌌", desc: "Đạt cảnh giới tối thượng Cổ Thần.",
                  rewardLT: 5000, titleId: "cothan") { $0.realm >= 14 },
    TNAchievement(id: "a_maxlv", name: "Đăng Phong Tạo Cực", emoji: "💯", desc: "Đạt cấp độ tối đa 100.",
                  rewardLT: 2000, titleId: "dangphong") { $0.level >= 100 },
    TNAchievement(id: "a_pvp", name: "Luận Kiếm Xưng Vương", emoji: "🏆", desc: "Đạt 1000 điểm danh vọng PvP.",
                  rewardLT: 1000, titleId: "kiemvuong") { $0.pvpPoints >= 1000 },
    TNAchievement(id: "a_pets", name: "Vạn Thú Quy Thuận", emoji: "🐾", desc: "Thu phục đủ 6 thú cưng.",
                  rewardLT: 800, titleId: "nguthu") { $0.ownedPets.count >= 6 },
    TNAchievement(id: "a_married", name: "Kết Tóc Se Duyên", emoji: "💞", desc: "Kết duyên đạo lữ.",
                  rewardLT: 500, titleId: "quyenlu") { !$0.spouse.isEmpty },
    TNAchievement(id: "a_vip", name: "Đại Hào Khách", emoji: "👑", desc: "Đạt VIP 3 trở lên.",
                  rewardLT: 1000, titleId: "haophu") { $0.vip >= 3 },
]

// MARK: - Trang bị (túi đồ) — vật phẩm sinh ngẫu nhiên có độ hiếm
struct TNGearData: Codable, Identifiable, Equatable {
    var id = UUID()
    var slot: String     // "weapon","armor","accessory"
    var rarity: Int      // 0 Phàm · 1 Linh · 2 Bảo · 3 Tiên · 4 Thần
    var atk: Int; var def: Int; var hp: Int
    var nameIdx: Int
}
func tnRarityName(_ r: Int) -> String { ["Phàm Phẩm","Linh Phẩm","Bảo Phẩm","Tiên Phẩm","Thần Phẩm"][min(max(r,0),4)] }
func tnRarityColor(_ r: Int) -> Color { [.gray, .green, .blue, .purple, .orange][min(max(r,0),4)] }
func tnSlotName(_ s: String) -> String { s == "weapon" ? "Vũ Khí" : (s == "armor" ? "Giáp" : "Phụ Kiện") }
func tnSlotIcon(_ s: String) -> String { s == "weapon" ? "🗡️" : (s == "armor" ? "🛡️" : "💍") }
private let TN_GEAR_NAMES: [String: [String]] = [
    "weapon": ["Phi Kiếm", "Huyết Đao", "Lôi Thương", "Cổ Kiếm", "Sát Thần Kích", "Đồ Long Đao"],
    "armor": ["Linh Giáp", "Kim Cang Giáp", "Băng Tơ Bào", "Long Lân Giáp", "Thánh Quang Khải", "Bất Diệt Thần Giáp"],
    "accessory": ["Trữ Vật Nhẫn", "Hộ Tâm Kính", "Tụ Linh Bội", "Cửu Chuyển Châu", "Thiên Đạo Ngọc", "Hỗn Độn Linh Bài"],
]
func tnGearName(_ g: TNGearData) -> String {
    let arr = TN_GEAR_NAMES[g.slot] ?? ["Vật Phẩm"]
    return arr[g.nameIdx % arr.count]
}
// Sinh trang bị theo lực (power = realm*9+stage + level/4), độ hiếm thiên về power
func tnRollGear(power: Int, minRarity: Int = 0) -> TNGearData {
    let slots = ["weapon", "armor", "accessory"]
    let slot = slots.randomElement()!
    let roll = Int.random(in: 0..<100)
    var rarity: Int
    switch roll {
    case ..<45: rarity = 0
    case ..<73: rarity = 1
    case ..<90: rarity = 2
    case ..<98: rarity = 3
    default:    rarity = 4
    }
    rarity = max(rarity, minRarity)
    let mul = Double(rarity + 1)
    let base = Double(power + 4)
    let a = slot == "weapon" ? Int(base * mul * Double.random(in: 1.4...2.0)) : Int(base * mul * Double.random(in: 0.2...0.5))
    let d = slot == "armor" ? Int(base * mul * Double.random(in: 0.8...1.2)) : Int(base * mul * Double.random(in: 0.1...0.4))
    let h = slot == "accessory" ? Int(base * mul * Double.random(in: 4...7)) : Int(base * mul * Double.random(in: 1.5...3.5))
    return TNGearData(slot: slot, rarity: rarity, atk: a, def: d, hp: h, nameIdx: Int.random(in: 0...5))
}
func tnGearValue(_ g: TNGearData) -> Int { (g.atk + g.def + g.hp / 4) * (g.rarity + 1) + 30 }

// MARK: - Tâm pháp (nâng cấp bằng linh thạch → buff vĩnh viễn)
struct TNTechnique: Identifiable {
    let id: String; let name: String; let emoji: String; let maxLv: Int
    let perLv: String; let color: Color; let baseCost: Int
}
let TN_TECHNIQUES: [TNTechnique] = [
    TNTechnique(id: "satpha", name: "Sát Phạt Quyết", emoji: "⚔️", maxLv: 10, perLv: "+3% công/cấp", color: .red, baseCost: 300),
    TNTechnique(id: "luyenthe", name: "Luyện Thể Quyết", emoji: "❤️", maxLv: 10, perLv: "+2.5% máu/cấp", color: .green, baseCost: 300),
    TNTechnique(id: "kimcang", name: "Kim Cang Quyết", emoji: "🛡️", maxLv: 10, perLv: "+7 thủ/cấp", color: .cyan, baseCost: 250),
]
func tnTech(_ id: String) -> TNTechnique? { TN_TECHNIQUES.first { $0.id == id } }

// MARK: - Boss thế giới & Phụ bản (bí cảnh)
struct TNBoss: Identifiable {
    let id: String; let name: String; let emoji: String; let minRealm: Int
    let hpMul: Double; let atkMul: Double; let reward: Int; let dropRarity: Int; let desc: String
}
let TN_BOSSES: [TNBoss] = [
    TNBoss(id: "b1", name: "Hắc Giao Vương", emoji: "🐊", minRealm: 0, hpMul: 3.0, atkMul: 0.9, reward: 300, dropRarity: 1, desc: "Yêu giao ngàn năm ở Hắc Phong Đầm."),
    TNBoss(id: "b2", name: "Huyết Nguyệt Lang Vương", emoji: "🐺", minRealm: 1, hpMul: 4.0, atkMul: 1.0, reward: 600, dropRarity: 1, desc: "Sói vương khát máu dưới trăng đỏ."),
    TNBoss(id: "b3", name: "Cửu U Ma Tôn", emoji: "👹", minRealm: 3, hpMul: 5.5, atkMul: 1.15, reward: 1200, dropRarity: 2, desc: "Ma tôn cổ xưa phong ấn nơi Cửu U."),
    TNBoss(id: "b4", name: "Thượng Cổ Hỏa Long", emoji: "🐉", minRealm: 5, hpMul: 7.0, atkMul: 1.25, reward: 2400, dropRarity: 3, desc: "Chân long thượng cổ, thân phủ lửa thiêng."),
    TNBoss(id: "b5", name: "Hỗn Độn Cổ Thần", emoji: "🌌", minRealm: 8, hpMul: 10.0, atkMul: 1.4, reward: 5000, dropRarity: 4, desc: "Cổ thần hỗn độn — thử thách tối thượng."),
]
struct TNDungeon: Identifiable {
    let id: String; let name: String; let emoji: String; let minRealm: Int
    let waves: Int; let reward: Int; let desc: String; let color: Color
}
let TN_DUNGEONS: [TNDungeon] = [
    TNDungeon(id: "d1", name: "Tàng Kiếm Động", emoji: "🗿", minRealm: 0, waves: 3, reward: 400, desc: "Bí cảnh sơ cấp, 3 ải liên hoàn.", color: .green),
    TNDungeon(id: "d2", name: "Vạn Yêu Quật", emoji: "🕸️", minRealm: 2, waves: 4, reward: 900, desc: "Hang ổ vạn yêu, 4 ải khó nhằn.", color: .purple),
    TNDungeon(id: "d3", name: "Cửu Trùng Tiên Điện", emoji: "🏛️", minRealm: 5, waves: 5, reward: 2200, desc: "Tiên điện chín tầng, 5 ải hiểm ác.", color: .orange),
]

// MARK: - Điểm danh tích luỹ (thưởng theo chu kỳ 7 ngày)
struct TNCheckinReward: Identifiable {
    let id: Int; let linhThach: Int; let bonus: String
}
let TN_CHECKIN: [TNCheckinReward] = [
    TNCheckinReward(id: 0, linhThach: 80, bonus: ""),
    TNCheckinReward(id: 1, linhThach: 120, bonus: "🌿 x3"),
    TNCheckinReward(id: 2, linhThach: 160, bonus: "⛏️ x3"),
    TNCheckinReward(id: 3, linhThach: 220, bonus: ""),
    TNCheckinReward(id: 4, linhThach: 300, bonus: "🎁 Trang bị"),
    TNCheckinReward(id: 5, linhThach: 400, bonus: ""),
    TNCheckinReward(id: 6, linhThach: 700, bonus: "🎁 Trang bị hiếm"),
]

// MARK: - Vòng quay may mắn (giải thưởng ngẫu nhiên)
struct TNWheelPrize: Identifiable {
    let id = UUID(); let label: String; let emoji: String; let kind: String; let amount: Int; let color: Color
}
let TN_WHEEL: [TNWheelPrize] = [
    TNWheelPrize(label: "50 Linh Thạch", emoji: "💎", kind: "lt", amount: 50, color: .cyan),
    TNWheelPrize(label: "150 Linh Thạch", emoji: "💎", kind: "lt", amount: 150, color: .blue),
    TNWheelPrize(label: "5 Linh Thảo", emoji: "🌿", kind: "thao", amount: 5, color: .green),
    TNWheelPrize(label: "5 Khoáng Thạch", emoji: "⛏️", kind: "thach", amount: 5, color: .brown),
    TNWheelPrize(label: "300 Linh Thạch", emoji: "💰", kind: "lt", amount: 300, color: .yellow),
    TNWheelPrize(label: "Trang Bị Ngẫu Nhiên", emoji: "🎁", kind: "gear", amount: 0, color: .purple),
    TNWheelPrize(label: "20 Linh Thạch", emoji: "🪙", kind: "lt", amount: 20, color: .gray),
    TNWheelPrize(label: "ĐẠI THƯỞNG 888", emoji: "🏆", kind: "lt", amount: 888, color: .orange),
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
        s.totalWins += 1             // thống kê thành tựu
        logDaily("hunt")             // thắng trận → tiến độ nhiệm vụ ngày
        save()
    }
    // ===== Thành tựu & Danh hiệu =====
    func achievementDone(_ a: TNAchievement) -> Bool { a.check(s) }
    var pendingAchievements: Int { TN_ACHIEVEMENTS.filter { $0.check(s) && !s.claimedAch.contains($0.id) }.count }
    @discardableResult
    func claimAchievement(_ a: TNAchievement) -> String {
        guard a.check(s) else { return "❌ Chưa đạt điều kiện." }
        guard !s.claimedAch.contains(a.id) else { return "Đã lĩnh thưởng rồi." }
        s.claimedAch.append(a.id)
        s.linhThach += a.rewardLT
        if !s.unlockedTitles.contains(a.titleId) { s.unlockedTitles.append(a.titleId) }
        if s.activeTitle.isEmpty { s.activeTitle = a.titleId }   // tự đeo danh hiệu đầu tiên
        s.hp = min(s.hp, s.hpMax)
        save()
        let t = tnTitle(a.titleId)?.name ?? ""
        return "🎉 +\(a.rewardLT) linh thạch · Mở khoá danh hiệu「\(t)」!"
    }
    func setTitle(_ id: String) {
        if id.isEmpty || s.unlockedTitles.contains(id) { s.activeTitle = id; s.hp = min(s.hp, s.hpMax); save() }
    }

    // ===== Chợ giao dịch (mô phỏng: bán nguyên liệu · mua từ tán tu khác) =====
    func sellMaterial(_ kind: String, _ qty: Int) -> String {
        let price = 40   // giá bán mỗi đơn vị nguyên liệu
        if kind == "thao" {
            let n = min(qty, s.linhThao)
            guard n > 0 else { return "❌ Không còn linh thảo để bán." }
            s.linhThao -= n; s.linhThach += n * price; save()
            return "💰 Bán \(n) 🌿 linh thảo → +\(n * price) linh thạch."
        } else {
            let n = min(qty, s.khoangThach)
            guard n > 0 else { return "❌ Không còn khoáng thạch để bán." }
            s.khoangThach -= n; s.linhThach += n * price; save()
            return "💰 Bán \(n) ⛏️ khoáng thạch → +\(n * price) linh thạch."
        }
    }
    func buyListing(_ l: TNListing) -> String {
        guard s.linhThach >= l.price else { return "❌ Thiếu linh thạch (cần \(l.price))." }
        switch l.kind {
        case "thao":  s.linhThao += l.qty
        case "thach": s.khoangThach += l.qty
        case "pet":
            if s.ownedPets.contains(l.refId) { return "Bạn đã sở hữu \(l.name) rồi." }
            s.ownedPets.append(l.refId)
        case "skin":
            if s.ownedSkins.contains(l.refId) { return "Bạn đã sở hữu \(l.name) rồi." }
            s.ownedSkins.append(l.refId)
        case "wing":
            if s.ownedWings.contains(l.refId) { return "Bạn đã sở hữu \(l.name) rồi." }
            s.ownedWings.append(l.refId)
        case "mount":
            if s.ownedMounts.contains(l.refId) { return "Bạn đã sở hữu \(l.name) rồi." }
            s.ownedMounts.append(l.refId)
        default: break
        }
        s.linhThach -= l.price
        save()
        return "✅ Mua \(l.name) từ \(l.seller) — giá \(l.price) linh thạch!"
    }

    // ===== Túi đồ & trang bị =====
    var powerLevel: Int { s.realm * 9 + s.stage + s.level / 4 }
    func dropGear(minRarity: Int = 0) -> TNGearData {
        let g = tnRollGear(power: powerLevel, minRarity: minRarity)
        s.inventory.append(g)
        save()
        return g
    }
    func equipGear(_ g: TNGearData) {
        switch g.slot {
        case "weapon":    if let cur = s.equipWeapon { s.inventory.append(cur) }; s.equipWeapon = g
        case "armor":     if let cur = s.equipArmor { s.inventory.append(cur) }; s.equipArmor = g
        default:          if let cur = s.equipAccessory { s.inventory.append(cur) }; s.equipAccessory = g
        }
        s.inventory.removeAll { $0.id == g.id }
        s.hp = min(s.hp, s.hpMax)
        save()
    }
    func unequip(_ slot: String) {
        switch slot {
        case "weapon":    if let cur = s.equipWeapon { s.inventory.append(cur) }; s.equipWeapon = nil
        case "armor":     if let cur = s.equipArmor { s.inventory.append(cur) }; s.equipArmor = nil
        default:          if let cur = s.equipAccessory { s.inventory.append(cur) }; s.equipAccessory = nil
        }
        s.hp = min(s.hp, s.hpMax); save()
    }
    func sellGear(_ g: TNGearData) -> String {
        let v = tnGearValue(g)
        s.inventory.removeAll { $0.id == g.id }
        s.linhThach += v
        save()
        return "💰 Bán \(tnGearName(g)) → +\(v) linh thạch."
    }

    // ===== Tâm pháp =====
    func techLevel(_ id: String) -> Int { s.techniques[id] ?? 0 }
    func techCost(_ t: TNTechnique) -> Int { t.baseCost * (techLevel(t.id) + 1) }
    @discardableResult
    func upgradeTech(_ t: TNTechnique) -> String {
        let lv = techLevel(t.id)
        guard lv < t.maxLv else { return "Đã đạt cấp tối đa." }
        let cost = techCost(t)
        guard s.linhThach >= cost else { return "❌ Thiếu linh thạch (cần \(cost))." }
        s.linhThach -= cost
        s.techniques[t.id] = lv + 1
        s.hp = min(s.hp, s.hpMax)
        save()
        return "📖 \(t.name) → cấp \(lv + 1)!"
    }

    // ===== Điểm danh tích luỹ =====
    var checkinReady: Bool { s.lastCheckin != todayStr() }
    var checkinToday: Int { s.checkinCount % 7 }
    @discardableResult
    func doCheckin() -> String {
        guard checkinReady else { return "Hôm nay đã điểm danh rồi." }
        let idx = s.checkinCount % 7
        let r = TN_CHECKIN[idx]
        s.lastCheckin = todayStr()
        s.checkinCount += 1
        s.linhThach += r.linhThach
        var extra = ""
        if r.bonus.contains("🌿") { s.linhThao += 3; extra = " · 🌿 x3" }
        if r.bonus.contains("⛏️") { s.khoangThach += 3; extra = " · ⛏️ x3" }
        if r.bonus.contains("Trang bị") {
            let g = dropGear(minRarity: r.bonus.contains("hiếm") ? 2 : 1)
            extra = " · 🎁 \(tnRarityName(g.rarity)) \(tnGearName(g))"
        }
        save()
        return "📅 Điểm danh ngày \(idx + 1)/7: +\(r.linhThach) linh thạch\(extra)"
    }

    // ===== Vòng quay may mắn =====
    func spinWheel() -> (prize: TNWheelPrize, msg: String)? {
        let cost = 100
        guard s.linhThach >= cost else { return nil }
        s.linhThach -= cost
        let p = TN_WHEEL.randomElement()!
        var got = p.label
        switch p.kind {
        case "lt":    s.linhThach += p.amount
        case "thao":  s.linhThao += p.amount
        case "thach": s.khoangThach += p.amount
        case "gear":  let g = dropGear(minRarity: 1); got = "\(tnRarityName(g.rarity)) \(tnGearName(g))"
        default: break
        }
        save()
        return (p, "🎉 Trúng: \(got)!")
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
        Group {
            if !game.s.created {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.13),
                                            game.s.realmEnum.color.opacity(0.28),
                                            Color(red: 0.02, green: 0.03, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    TNCloudsBG()
                    TNCreateView(game: game)
                }
                .preferredColorScheme(.dark)
                .navigationTitle("Tiên Nghịch")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                // VÀO THẲNG MÀN GAME: thế giới di chuyển tự do (không còn menu nút)
                TNWorldView(game: game)
                    .navigationBarHidden(true)
            }
        }
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
    @State private var showAchieve = false
    @State private var showChat = false
    @State private var showMarket = false
    @State private var showBoss = false
    @State private var showBag = false
    @State private var showCheckin = false
    @State private var showTech = false
    @State private var showWorld = false

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
                if let tt = tnTitle(game.s.activeTitle) {
                    Text("『 \(tt.name) 』").font(.caption.bold()).foregroundStyle(tt.color)
                        .shadow(color: tt.color.opacity(0.7), radius: 4)
                }
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
                    // 🌍 VÀO THẾ GIỚI — chế độ di chuyển tự do bằng joystick (nổi bật nhất)
                    Button { showWorld = true } label: {
                        HStack {
                            Text("🌍").font(.system(size: 30))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VÀO THẾ GIỚI").font(.title3.bold()).foregroundStyle(.white)
                                Text("Di chuyển tự do · đánh quái · gặp NPC").font(.caption2).foregroundStyle(.white.opacity(0.85))
                            }
                            Spacer()
                            Image(systemName: "location.north.circle.fill").font(.title2).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .background(LinearGradient(colors: [.green, .teal, .blue], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .green.opacity(0.5), radius: 10)
                    }.buttonStyle(TNPress(glow: .green))

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
                    Button { showBoss = true } label: { bigBtn("👹 Boss Thế Giới & Phụ Bản", [.red, .purple]) }.buttonStyle(TNPress(glow: .red))
                    Button { showBag = true } label: { bigBtn("🎒 Túi Đồ & Trang Bị", [.brown, .yellow]) }.buttonStyle(TNPress(glow: .yellow))
                    Button { showTech = true } label: { bigBtn("📖 Tâm Pháp — Cây Kỹ Năng", [.indigo, .blue]) }.buttonStyle(TNPress(glow: .blue))
                    Button { showCheckin = true } label: { bigBtn("📅 Điểm Danh & Vòng Quay", [.pink, .orange]) }.buttonStyle(TNPress(glow: .pink))
                    Button { showMap = true } label: { bigBtn("🗺️ Bản Đồ — Khám Phá Vùng Đất", [.green, .teal]) }.buttonStyle(TNPress(glow: .green))
                    Button { showPets = true } label: { bigBtn("🐾 Thú Cưng Đồng Hành", [.orange, .pink]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showFashion = true } label: { bigBtn("👗 Thời Trang — Cánh & Hào Quang", [.purple, .pink]) }.buttonStyle(TNPress(glow: .purple))
                    Button { showChat = true } label: { bigBtn("💬 Thế Giới Chat — Giao Lưu", [.blue, .cyan]) }.buttonStyle(TNPress(glow: .cyan))
                    Button { showMarket = true } label: { bigBtn("🏪 Chợ Giao Dịch — Mua Bán", [.brown, .orange]) }.buttonStyle(TNPress(glow: .orange))
                    Button { tab = 1 } label: { bigBtn("📖 Đi Theo Cốt Truyện", [.brown, .orange]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showForge = true } label: { bigBtn("⚒️ Chế Tạo — Luyện Khí · Luyện Đan", [.gray, .brown]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showArena = true } label: { bigBtn("🏆 Đấu Đài — Thách Đấu Cao Thủ", [.yellow, .orange]) }.buttonStyle(TNPress(glow: .yellow))
                    Button { showPvP = true } label: { bigBtn("⚔️ PvP Xếp Hạng — Đấu Danh Vọng", [.red, .pink]) }.buttonStyle(TNPress(glow: .red))
                    Button { showGuild = true } label: { bigBtn("🏯 Bang Hội — Gia Nhập Thế Lực", [.indigo, .cyan]) }.buttonStyle(TNPress(glow: .cyan))
                    Button { showMount = true } label: { bigBtn("🐲 Thú Cưỡi Bay — Ngự Không Phi Hành", [.blue, .indigo]) }.buttonStyle(TNPress(glow: .blue))
                    Button { showSpouse = true } label: { bigBtn("💞 Đạo Lữ — Kết Duyên Tu Tiên", [.pink, .red]) }.buttonStyle(TNPress(glow: .pink))
                    Button { showRecharge = true } label: { bigBtn("💰 Nạp Linh Thạch — Cửa Hàng", [.yellow, .green]) }.buttonStyle(TNPress(glow: .green))
                    Button { showVip = true } label: { bigBtn("👑 VIP Đặc Quyền", [.orange, .yellow]) }.buttonStyle(TNPress(glow: .orange))
                    Button { showAchieve = true } label: {
                        ZStack(alignment: .topTrailing) {
                            bigBtn("🏅 Thành Tựu & Danh Hiệu", [.teal, .green])
                            if game.pendingAchievements > 0 {
                                Text("\(game.pendingAchievements)").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(6).background(.red, in: Circle()).offset(x: -8, y: -8)
                            }
                        }
                    }.buttonStyle(TNPress(glow: .green))
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
        .fullScreenCover(isPresented: $showWorld) { TNWorldView(game: game) }
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
        .sheet(isPresented: $showAchieve) { TNAchieveView(game: game) }
        .sheet(isPresented: $showChat) { TNChatView(game: game) }
        .sheet(isPresented: $showMarket) { TNMarketView(game: game) }
        .fullScreenCover(isPresented: $showBoss) { TNBossView(game: game) }
        .sheet(isPresented: $showBag) { TNBagView(game: game) }
        .sheet(isPresented: $showCheckin) { TNCheckinView(game: game) }
        .sheet(isPresented: $showTech) { TNTechView(game: game) }
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
        TNHaptic.hit(.light); TNSound.hit()
        hitEnemy(d, "\(game.s.name) vung quyền!", .white)
    }
    private func useSkill(_ sk: TNSkill) {
        guard mp >= sk.mp else { return }
        mp -= sk.mp
        var d = max(5, Int(Double(game.s.atk) * sk.power * Double.random(in: 0.9...1.15)) - enemy.def)
        fx = (sk.color, sk.icon)
        TNHaptic.hit(sk.element == "than" ? .heavy : .medium); TNSound.cast()
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
                TNHaptic.success(); TNSound.win()
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

// MARK: - Thành Tựu & Danh Hiệu (lĩnh thưởng · chọn danh hiệu đeo)
struct TNAchieveView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0            // 0: thành tựu · 1: danh hiệu
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🏅 THÀNH TỰU").font(.title3.bold()).foregroundStyle(.green)
                        Spacer()
                        Text("Đã đạt \(game.s.claimedAch.count)/\(TN_ACHIEVEMENTS.count)")
                            .font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                    }.padding(.horizontal).padding(.top, 8)

                    Picker("", selection: $tab) {
                        Text("Thành Tựu").tag(0); Text("Danh Hiệu").tag(1)
                    }.pickerStyle(.segmented).padding(.horizontal)

                    if tab == 0 {
                        ForEach(TN_ACHIEVEMENTS) { a in achRow(a) }
                    } else {
                        titleSection
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.04,green:0.1,blue:0.08), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thành Tựu").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private func achRow(_ a: TNAchievement) -> some View {
        let done = game.achievementDone(a)
        let claimed = game.s.claimedAch.contains(a.id)
        HStack(spacing: 12) {
            Text(a.emoji).font(.system(size: 30)).frame(width: 50, height: 50)
                .background((done ? Color.green.opacity(0.2) : Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
                .grayscale(done ? 0 : 0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.subheadline.bold()).foregroundStyle(.white)
                Text(a.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text("🎁 +\(a.rewardLT) 💎 · 🏷️ \(tnTitle(a.titleId)?.name ?? "")")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.teal)
            }
            Spacer()
            Button {
                msg = game.claimAchievement(a); TNHaptic.success()
            } label: {
                Text(claimed ? "✓" : (done ? "Lĩnh" : "🔒"))
                    .font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 50).padding(.vertical, 8)
                    .background(claimed ? Color.gray.opacity(0.5) : (done ? Color.green : Color.gray), in: Capsule())
            }
            .disabled(claimed || !done)
            .buttonStyle(TNPress(glow: .green))
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
    }

    private var titleSection: some View {
        VStack(spacing: 10) {
            Text("Chọn danh hiệu để đeo cạnh tên — cộng chỉ số uy danh.")
                .font(.caption2).foregroundStyle(.white.opacity(0.55)).padding(.horizontal)
            // Bỏ danh hiệu
            Button { game.setTitle("") } label: {
                Text(game.s.activeTitle.isEmpty ? "• Không đeo danh hiệu (đang chọn)" : "Bỏ đeo danh hiệu")
                    .font(.caption.bold()).foregroundStyle(game.s.activeTitle.isEmpty ? .green : .white.opacity(0.7))
            }
            ForEach(TN_TITLES) { t in
                let unlocked = game.s.unlockedTitles.contains(t.id)
                let active = game.s.activeTitle == t.id
                HStack(spacing: 12) {
                    Text("🏷️").font(.system(size: 24)).frame(width: 44, height: 44)
                        .background(t.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12)).grayscale(unlocked ? 0 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("『 \(t.name) 』").font(.subheadline.bold()).foregroundStyle(unlocked ? t.color : .white.opacity(0.4))
                        Text("⚔️+\(t.atk) ❤️+\(t.hp)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if active { Text("Đang đeo").font(.caption.bold()).foregroundStyle(.green) }
                    else if unlocked {
                        Button("Đeo") { game.setTitle(t.id) }.font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7).background(t.color, in: Capsule())
                    } else {
                        Text("🔒 Khoá").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                .opacity(unlocked ? 1 : 0.6)
            }
        }
    }
}

// MARK: - Dữ liệu Chat & Chợ (mô phỏng tán tu khác trong thế giới)
let TN_BOT_NAMES = ["Hàn Lập", "Diệp Phàm", "Tiêu Viêm", "Đường Tam", "Lâm Động", "Mạnh Hạo",
                    "Sở Phong", "La Phong", "Tần Vũ", "Cố Ẩn", "Bạch Tiểu Thuần", "Vân Vận",
                    "Nam Cung Uyển", "Tuyết Nhi", "Hạ Hầu", "Vô Danh Kiếm Khách"]
let TN_CHAT_LINES = [
    "Có ai tổ đội đánh Boss Hắc Phong Lâm không?", "Vừa đột phá Kết Đan, phê quá 😎",
    "Bán phi kiếm +5 giá hữu nghị, ib nhé.", "Bang ta đang tuyển thành viên chăm chỉ!",
    "Ai chỉ mình cách luyện đan với 🙏", "PvP hôm nay khó quá, toàn cao thủ.",
    "Vừa cưới đạo lữ, mời cả server ăn cỗ 🎉", "Rớt được Hỏa Phượng Cánh, hên xỉu!",
    "Thiên Long Bang vô địch thiên hạ!", "Có ai bán khoáng thạch không, thu giá cao.",
    "Mới lên VIP, quà ngon thật sự.", "Đấu Đài ải 8 khó nhằn quá anh em ơi.",
    "Cày cấp 100 mỏi tay ghê 😅", "Thần thú Kim Ô mạnh vô đối!",
    "Chúc cả server tu luyện tinh tấn 🙌", "Ai rảnh giao lưu tỷ thí không?"]

// Một mục rao bán trên chợ
struct TNListing: Identifiable {
    let id = UUID()
    let seller: String; let name: String; let emoji: String; let price: Int
    let kind: String     // "thao","thach","pet","skin","wing","mount"
    let refId: String; let qty: Int; let color: Color
}
// Sinh danh sách rao bán ngẫu nhiên từ "tán tu khác"
func tnGenMarket() -> [TNListing] {
    var out: [TNListing] = []
    // Nguyên liệu
    for _ in 0..<3 {
        let q = Int.random(in: 5...20)
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: "\(q) Linh Thảo", emoji: "🌿",
                             price: q * Int.random(in: 30...45), kind: "thao", refId: "", qty: q, color: .green))
        let q2 = Int.random(in: 5...20)
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: "\(q2) Khoáng Thạch", emoji: "⛏️",
                             price: q2 * Int.random(in: 30...45), kind: "thach", refId: "", qty: q2, color: .brown))
    }
    // Vật phẩm hiếm từ tán tu khác
    if let p = TN_PETS.randomElement() {
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: p.name, emoji: p.emoji,
                             price: Int(Double(p.price) * Double.random(in: 0.8...1.1)), kind: "pet", refId: p.id, qty: 1, color: p.color))
    }
    if let w = TN_WINGS.filter({ $0.id != "none" }).randomElement() {
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: w.name, emoji: w.emoji,
                             price: Int(Double(w.price) * Double.random(in: 0.8...1.1)), kind: "wing", refId: w.id, qty: 1, color: w.colors.first!))
    }
    if let m = TN_MOUNTS.randomElement() {
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: m.name, emoji: m.emoji,
                             price: Int(Double(m.price) * Double.random(in: 0.8...1.1)), kind: "mount", refId: m.id, qty: 1, color: m.color))
    }
    if let sk = TN_SKINS.filter({ $0.price > 0 }).randomElement() {
        out.append(TNListing(seller: TN_BOT_NAMES.randomElement()!, name: sk.name, emoji: "👘",
                             price: Int(Double(sk.price) * Double.random(in: 0.8...1.1)), kind: "skin", refId: sk.id, qty: 1, color: sk.colors.first!))
    }
    return out.shuffled()
}

// MARK: - Thế Giới Chat (mô phỏng · có tán tu bot trò chuyện + gửi tin)
struct TNChatMsg: Identifiable { let id = UUID(); let sender: String; let text: String; let me: Bool; let color: Color }
struct TNChatView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msgs: [TNChatMsg] = []
    @State private var input = ""
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private let botColors: [Color] = [.cyan, .green, .orange, .pink, .yellow, .mint, .teal]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("💬 Kênh Thế Giới · mô phỏng — trò chuyện cùng tán tu")
                    .font(.caption2).foregroundStyle(.white.opacity(0.55)).padding(.vertical, 6)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(msgs) { m in
                                HStack(alignment: .top, spacing: 6) {
                                    if m.me { Spacer(minLength: 40) }
                                    VStack(alignment: m.me ? .trailing : .leading, spacing: 2) {
                                        Text(m.me ? "Ta" : m.sender).font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(m.me ? .yellow : m.color)
                                        Text(m.text).font(.footnote).foregroundStyle(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(m.me ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                                                        in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    if !m.me { Spacer(minLength: 40) }
                                }.id(m.id)
                            }
                        }.padding(.horizontal)
                    }
                    .onChange(of: msgs.count) { _ in
                        if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Nhập tin nhắn…", text: $input)
                        .textFieldStyle(.plain).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(.white.opacity(0.1), in: Capsule())
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill").foregroundStyle(.white)
                            .padding(11).background(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue, in: Circle())
                    }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(10)
            }
            .background(LinearGradient(colors: [Color(red:0.04,green:0.07,blue:0.13), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thế Giới Chat").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
            .onAppear { if msgs.isEmpty { for _ in 0..<5 { addBot() } } }
            .onReceive(timer) { _ in addBot() }
        }
    }
    private func send() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        msgs.append(TNChatMsg(sender: game.s.name, text: t, me: true, color: .yellow))
        input = ""
        // Đôi khi có tán tu đáp lời
        if Bool.random() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1...2.5)) { addBot() }
        }
    }
    private func addBot() {
        let name = TN_BOT_NAMES.randomElement()!
        msgs.append(TNChatMsg(sender: name, text: TN_CHAT_LINES.randomElement()!, me: false, color: botColors.randomElement()!))
        if msgs.count > 40 { msgs.removeFirst(msgs.count - 40) }
    }
}

// MARK: - Chợ Giao Dịch (mô phỏng · bán nguyên liệu · mua vật phẩm từ tán tu khác)
struct TNMarketView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var listings: [TNListing] = []
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🏪 CHỢ GIAO DỊCH").font(.title3.bold()).foregroundStyle(.orange)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)
                    Text("Mua bán mô phỏng với tán tu khác trong thế giới.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))

                    // Bán nhanh nguyên liệu
                    VStack(spacing: 8) {
                        Text("💰 Bán nguyên liệu (40 💎/đơn vị)").font(.caption.bold()).foregroundStyle(.yellow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            sellBtn("🌿 Bán 5", "thao", 5); sellBtn("🌿 Bán tất cả", "thao", 999)
                        }
                        HStack(spacing: 10) {
                            sellBtn("⛏️ Bán 5", "thach", 5); sellBtn("⛏️ Bán tất cả", "thach", 999)
                        }
                        Text("Kho: 🌿 \(game.s.linhThao) · ⛏️ \(game.s.khoangThach)")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)

                    HStack {
                        Text("🛒 Rao bán từ tán tu khác").font(.caption.bold()).foregroundStyle(.orange)
                        Spacer()
                        Button { listings = tnGenMarket(); flash("🔄 Đã làm mới chợ.") } label: {
                            Label("Làm mới", systemImage: "arrow.clockwise").font(.caption.bold()).foregroundStyle(.cyan)
                        }
                    }.padding(.horizontal)

                    ForEach(listings) { l in
                        HStack(spacing: 12) {
                            Text(l.emoji).font(.system(size: 30)).frame(width: 50, height: 50)
                                .background(l.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(.subheadline.bold()).foregroundStyle(.white)
                                Text("Người bán: \(l.seller)").font(.caption2).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Button("💎\(l.price)") { flash(game.buyListing(l)); TNHaptic.hit() }
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(game.s.linhThach >= l.price ? l.color : Color.gray, in: Capsule())
                                .buttonStyle(TNPress(glow: l.color))
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }

                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.1,green:0.07,blue:0.03), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Chợ Giao Dịch").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
            .onAppear { if listings.isEmpty { listings = tnGenMarket() } }
        }
    }
    private func sellBtn(_ label: String, _ kind: String, _ qty: Int) -> some View {
        Button { flash(game.sellMaterial(kind, qty)) } label: {
            Text(label).font(.caption.bold()).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(.green.opacity(0.8), in: Capsule())
        }.buttonStyle(TNPress(glow: .green))
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Boss Thế Giới & Phụ Bản
struct TNBossView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var fightBoss: TNBoss?
    @State private var fightDungeon: TNDungeon?
    @State private var showFight = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.1,green:0.03,blue:0.12), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TNCloudsBG()
            VStack(spacing: 0) {
                HStack {
                    Text("👹 BOSS & PHỤ BẢN").font(.title3.bold()).foregroundStyle(.red)
                    Spacer(); Button("Đóng") { dismiss() }.foregroundStyle(.white)
                }.padding()
                Picker("", selection: $tab) {
                    Text("Boss Thế Giới").tag(0); Text("Phụ Bản").tag(1)
                }.pickerStyle(.segmented).padding(.horizontal)
                ScrollView {
                    VStack(spacing: 10) {
                        if tab == 0 {
                            ForEach(TN_BOSSES) { b in bossRow(b) }
                        } else {
                            ForEach(TN_DUNGEONS) { d in dungeonRow(d) }
                        }
                        Color.clear.frame(height: 20)
                    }.padding(.top, 10)
                }
                if let toast {
                    Text(toast).font(.footnote.bold()).foregroundStyle(.yellow)
                        .padding(10).background(.black.opacity(0.6), in: Capsule()).padding(.bottom, 10)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFight) {
            TNBattleView(game: game, enemy: currentEnemy(), storyMode: true) { won in
                if won {
                    if let b = fightBoss {
                        let g = game.dropGear(minRarity: b.dropRarity)
                        flash("🎉 Hạ gục \(b.name)! Rơi \(tnRarityName(g.rarity)) \(tnGearName(g)) 🎁")
                    } else if let d = fightDungeon {
                        if !game.s.clearedDungeons.contains(d.id) { game.s.clearedDungeons.append(d.id); game.save() }
                        let g = game.dropGear(minRarity: 2)
                        flash("🏆 Vượt \(d.name)! Rơi \(tnRarityName(g.rarity)) \(tnGearName(g)) 🎁")
                    }
                }
            }
        }
    }

    @ViewBuilder private func bossRow(_ b: TNBoss) -> some View {
        let locked = game.s.realm < b.minRealm
        HStack(spacing: 12) {
            Text(b.emoji).font(.system(size: 34)).frame(width: 56, height: 56)
                .background(.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .overlay(locked ? Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.8)) : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name).font(.subheadline.bold()).foregroundStyle(.white)
                Text(b.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text("💎 \(b.reward) · 🎁 rơi \(tnRarityName(b.dropRarity))+").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
            }
            Spacer()
            if locked {
                Text("Cần \(TNRealm(rawValue: b.minRealm)?.name ?? "")").font(.caption2).foregroundStyle(.white.opacity(0.5)).frame(width: 70)
            } else {
                Button("Khiêu chiến") { fightBoss = b; fightDungeon = nil; showFight = true }
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.red, in: Capsule())
                    .buttonStyle(TNPress(glow: .red))
            }
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).opacity(locked ? 0.55 : 1).padding(.horizontal)
    }

    @ViewBuilder private func dungeonRow(_ d: TNDungeon) -> some View {
        let locked = game.s.realm < d.minRealm
        let cleared = game.s.clearedDungeons.contains(d.id)
        HStack(spacing: 12) {
            Text(d.emoji).font(.system(size: 34)).frame(width: 56, height: 56)
                .background(d.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                .overlay(locked ? Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.8)) : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.subheadline.bold()).foregroundStyle(.white)
                Text(d.desc).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text("⚔️ \(d.waves) ải · 💎 \(d.reward)\(cleared ? " · ✅ đã vượt" : "")").font(.system(size: 10, weight: .bold)).foregroundStyle(d.color)
            }
            Spacer()
            if locked {
                Text("Cần \(TNRealm(rawValue: d.minRealm)?.name ?? "")").font(.caption2).foregroundStyle(.white.opacity(0.5)).frame(width: 70)
            } else {
                Button("Vào phụ bản") { fightDungeon = d; fightBoss = nil; showFight = true }
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(d.color, in: Capsule())
                    .buttonStyle(TNPress(glow: d.color))
            }
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).opacity(locked ? 0.55 : 1).padding(.horizontal)
    }

    private func currentEnemy() -> TNEnemy {
        if let b = fightBoss {
            let hp = Int(Double(game.s.hpMax) * b.hpMul)
            return TNEnemy(name: b.name, emoji: b.emoji, hp: hp, hpMax: hp,
                           atk: Int(Double(game.s.atk) * 0.8 * b.atkMul), def: Int(Double(game.s.def) * 0.9),
                           reward: b.reward, exp: b.reward, isBoss: true)
        } else if let d = fightDungeon {
            let hp = Int(Double(game.s.hpMax) * Double(d.waves) * 1.2)
            return TNEnemy(name: "\(d.name) · Thủ Lĩnh", emoji: d.emoji, hp: hp, hpMax: hp,
                           atk: Int(Double(game.s.atk) * 0.72), def: Int(Double(game.s.def) * 0.85),
                           reward: d.reward, exp: d.reward, isBoss: true)
        }
        let hp = game.s.hpMax * 2
        return TNEnemy(name: "Yêu Thú", emoji: "🐺", hp: hp, hpMax: hp, atk: game.s.atk / 2, def: game.s.def / 2, reward: 100, exp: 100, isBoss: true)
    }
    private func flash(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { if toast == m { toast = nil } } }
    }
}

// MARK: - Túi Đồ & Trang Bị
struct TNBagView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("🎒 TÚI ĐỒ").font(.title3.bold()).foregroundStyle(.yellow)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)

                    // Đang mặc
                    VStack(spacing: 8) {
                        Text("Đang trang bị").font(.caption.bold()).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading)
                        equippedRow("weapon", game.s.equipWeapon)
                        equippedRow("armor", game.s.equipArmor)
                        equippedRow("accessory", game.s.equipAccessory)
                        Text("Tổng lực chiến: ⚔️\(game.s.atk) · 🛡️\(game.s.def) · ❤️\(game.s.hpMax)")
                            .font(.caption2.bold()).foregroundStyle(.orange).padding(.top, 2)
                    }
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)

                    Text("Kho đồ (\(game.s.inventory.count))").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    if game.s.inventory.isEmpty {
                        Text("Túi trống — đánh Boss / phụ bản / điểm danh để nhặt trang bị.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5)).padding()
                    }
                    ForEach(game.s.inventory) { g in gearRow(g) }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.09,green:0.07,blue:0.03), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Túi Đồ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    @ViewBuilder private func equippedRow(_ slot: String, _ g: TNGearData?) -> some View {
        HStack(spacing: 10) {
            Text(tnSlotIcon(slot)).font(.system(size: 24)).frame(width: 40)
            if let g {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(tnGearName(g))").font(.subheadline.bold()).foregroundStyle(tnRarityColor(g.rarity))
                    Text("⚔️+\(g.atk) 🛡️+\(g.def) ❤️+\(g.hp)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button("Tháo") { game.unequip(slot) }.font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.gray.opacity(0.7), in: Capsule())
            } else {
                Text("[\(tnSlotName(slot))] — trống").font(.caption).foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
        }
    }
    @ViewBuilder private func gearRow(_ g: TNGearData) -> some View {
        HStack(spacing: 12) {
            Text(tnSlotIcon(g.slot)).font(.system(size: 28)).frame(width: 48, height: 48)
                .background(tnRarityColor(g.rarity).opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tnGearName(g))").font(.subheadline.bold()).foregroundStyle(tnRarityColor(g.rarity))
                Text("\(tnRarityName(g.rarity)) · \(tnSlotName(g.slot))").font(.caption2).foregroundStyle(.white.opacity(0.55))
                Text("⚔️+\(g.atk) 🛡️+\(g.def) ❤️+\(g.hp)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            VStack(spacing: 5) {
                Button("Mặc") { game.equipGear(g); flash("✅ Đã trang bị \(tnGearName(g))") }
                    .font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(.blue, in: Capsule())
                Button("Bán 💎\(tnGearValue(g))") { flash(game.sellGear(g)) }
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.green.opacity(0.7), in: Capsule())
            }
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
    }
    private func flash(_ m: String) {
        withAnimation { msg = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if msg == m { msg = nil } } }
    }
}

// MARK: - Tâm Pháp (cây kỹ năng nâng cấp)
struct TNTechView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("📖 TÂM PHÁP").font(.title3.bold()).foregroundStyle(.indigo)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)
                    Text("Tu luyện tâm pháp để tăng chỉ số vĩnh viễn.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    ForEach(TN_TECHNIQUES) { t in
                        let lv = game.techLevel(t.id)
                        let maxed = lv >= t.maxLv
                        let cost = game.techCost(t)
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Text(t.emoji).font(.system(size: 32)).frame(width: 54, height: 54)
                                    .background(t.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.headline).foregroundStyle(.white)
                                    Text(t.perLv).font(.caption2).foregroundStyle(t.color)
                                    Text("Cấp \(lv)/\(t.maxLv)").font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer()
                                Button(maxed ? "TỐI ĐA" : "💎\(cost)") { msg = game.upgradeTech(t); TNHaptic.success() }
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(maxed ? Color.gray : (game.s.linhThach >= cost ? t.color : Color.gray), in: Capsule())
                                    .disabled(maxed)
                            }
                            // Thanh cấp
                            GeometryReader { geo in
                                HStack(spacing: 3) {
                                    ForEach(0..<t.maxLv, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(i < lv ? t.color : Color.white.opacity(0.12))
                                            .frame(height: 6)
                                    }
                                }.frame(width: geo.size.width)
                            }.frame(height: 6)
                        }
                        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    }
                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.05,green:0.05,blue:0.13), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Tâm Pháp").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Điểm Danh & Vòng Quay May Mắn
struct TNCheckinView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var msg: String?
    @State private var spinning = false
    @State private var spinPrize: TNWheelPrize?
    @State private var wheelIdx = 0
    private let spinTimer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("📅 ĐIỂM DANH").font(.title3.bold()).foregroundStyle(.pink)
                        Spacer(); Text("💎 \(game.s.linhThach)").foregroundStyle(.cyan).bold()
                    }.padding(.horizontal).padding(.top, 8)

                    // Lịch điểm danh 7 ngày
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(TN_CHECKIN) { r in
                            let done = game.s.checkinCount > 0 && r.id < game.checkinToday
                            let isToday = r.id == game.checkinToday && game.checkinReady
                            VStack(spacing: 3) {
                                Text("Ngày \(r.id + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                                Text(r.bonus.isEmpty ? "💎" : "🎁").font(.system(size: 22))
                                Text("\(r.linhThach)").font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background((isToday ? Color.pink.opacity(0.3) : Color.white.opacity(0.05)), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isToday ? .pink : .clear, lineWidth: 1.5))
                            .overlay(alignment: .topTrailing) { if done { Text("✓").font(.system(size: 10, weight: .heavy)).foregroundStyle(.green).padding(3) } }
                        }
                    }.padding(.horizontal)

                    Button { msg = game.doCheckin(); TNHaptic.success() } label: {
                        Text(game.checkinReady ? "📅 ĐIỂM DANH HÔM NAY" : "✓ Đã điểm danh hôm nay")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(game.checkinReady ? LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }.disabled(!game.checkinReady).buttonStyle(TNPress(glow: .pink)).padding(.horizontal)
                    Text("Đã điểm danh tích luỹ \(game.s.checkinCount) ngày").font(.caption2).foregroundStyle(.white.opacity(0.6))

                    Divider().background(.white.opacity(0.2)).padding(.horizontal)

                    // Vòng quay may mắn
                    Text("🎡 VÒNG QUAY MAY MẮN").font(.subheadline.bold()).foregroundStyle(.orange)
                    Text(TN_WHEEL[wheelIdx].emoji).font(.system(size: 60))
                        .scaleEffect(spinning ? 1.15 : 1.0)
                    Text(TN_WHEEL[wheelIdx].label).font(.caption.bold()).foregroundStyle(TN_WHEEL[wheelIdx].color)
                    Button { spin() } label: {
                        Text(spinning ? "Đang quay…" : "🎡 QUAY (100 💎)")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }.disabled(spinning || game.s.linhThach < 100).buttonStyle(TNPress(glow: .orange)).padding(.horizontal)

                    if let msg { Text(msg).font(.footnote.bold()).foregroundStyle(.yellow).multilineTextAlignment(.center).padding(.horizontal) }
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red:0.12,green:0.05,blue:0.08), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Điểm Danh & Vòng Quay").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
            .onReceive(spinTimer) { _ in if spinning { wheelIdx = (wheelIdx + 1) % TN_WHEEL.count } }
        }
    }
    private func spin() {
        guard let result = game.spinWheel() else { msg = "❌ Thiếu linh thạch (cần 100)."; return }
        spinning = true; msg = nil
        // Dừng ở ô trúng sau ~1.6s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            spinning = false
            if let idx = TN_WHEEL.firstIndex(where: { $0.id == result.prize.id }) { wheelIdx = idx }
            msg = result.msg
            TNHaptic.success()
        }
    }
}

// ============================================================================
//  🌍 THẾ GIỚI DI CHUYỂN TỰ DO — điều khiển nhân vật bằng joystick như game mobile
// ============================================================================
let TN_WORLD_SIZE: CGFloat = 2200

struct TNDecor: Identifiable { let id = UUID(); let pos: CGPoint; let emoji: String; let size: CGFloat }
// Trang trí cảnh vật rải đều thế giới (cây, đá, cỏ, hoa…)
let TN_DECOR: [TNDecor] = {
    var out: [TNDecor] = []
    let deco = ["🌲","🌲","🌳","🪨","🌿","🌸","🍄","⛰️","🌾","🎋"]
    var seed: UInt64 = 20260705
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 100000) / 100000 }
    for _ in 0..<70 {
        let x = 80 + rnd() * (TN_WORLD_SIZE - 160)
        let y = 80 + rnd() * (TN_WORLD_SIZE - 160)
        let e = deco[Int(rnd() * CGFloat(deco.count)) % deco.count]
        out.append(TNDecor(pos: CGPoint(x: x, y: y), emoji: e, size: 26 + rnd() * 26))
    }
    return out
}()

struct TNWorldMob: Identifiable {
    let id = UUID()
    var pos: CGPoint
    let name: String
    let emoji: String
    var alive = true
    var respawnAt: Date? = nil
}
func tnMakeMobs() -> [TNWorldMob] {
    let kinds = [("Yêu Lang","🐺"),("Sơn Trư","🐗"),("Độc Xà","🐍"),("Hắc Hùng","🐻"),
                 ("Yêu Hồ","🦊"),("Độc Chu","🕷️"),("Huyết Bức","🦇"),("Thạch Quái","🗿")]
    var out: [TNWorldMob] = []
    var seed: UInt64 = 77777
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 100000) / 100000 }
    for i in 0..<16 {
        let x = 150 + rnd() * (TN_WORLD_SIZE - 300)
        let y = 150 + rnd() * (TN_WORLD_SIZE - 300)
        let k = kinds[i % kinds.count]
        out.append(TNWorldMob(pos: CGPoint(x: x, y: y), name: k.0, emoji: k.1))
    }
    return out
}

// NPC thân thiện trong thế giới
struct TNWorldNPC: Identifiable {
    let id = UUID(); let pos: CGPoint; let name: String; let emoji: String; let line: String; let action: String
}
let TN_WORLD_NPCS: [TNWorldNPC] = [
    TNWorldNPC(pos: CGPoint(x: 1100, y: 1100), name: "Trưởng Lão", emoji: "🧙", line: "Hậu bối, chăm chỉ tu luyện sẽ có ngày phi thăng!", action: "quest"),
    TNWorldNPC(pos: CGPoint(x: 700, y: 900), name: "Thương Nhân", emoji: "🧕", line: "Ghé xem hàng hoá của lão phu chứ?", action: "market"),
    TNWorldNPC(pos: CGPoint(x: 1500, y: 800), name: "Thiết Tượng", emoji: "🧔", line: "Trang bị tốt cần rèn giũa. Vào lò chứ?", action: "forge"),
]

// Cần joystick điều khiển
struct TNJoystick: View {
    @Binding var vec: CGVector
    var size: CGFloat = 130
    @State private var thumb: CGSize = .zero
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.1))
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.5), .white.opacity(0.2)], center: .center, startRadius: 0, endRadius: 30))
                .frame(width: size * 0.42, height: size * 0.42).offset(thumb)
                .shadow(color: .cyan.opacity(0.5), radius: 6)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let r = size / 2
                    var dx = g.location.x - r, dy = g.location.y - r
                    let mag = sqrt(dx * dx + dy * dy)
                    if mag > r { dx = dx / mag * r; dy = dy / mag * r }
                    thumb = CGSize(width: dx, height: dy)
                    vec = CGVector(dx: dx / r, dy: dy / r)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2)) { thumb = .zero }
                    vec = .zero
                }
        )
    }
}

// Điểm đến các tính năng (mở dạng bảng trong game, không còn menu nút cũ)
enum TNRoute: String, Identifiable {
    case quest, story, skills, shop, map, pets, fashion, guild, pvp, spouse, mount
    case recharge, vip, achieve, boss, tech, checkin, chat, market, forge, arena, codex, bag
    var id: String { rawValue }
}
// Một mục trong bảng chức năng (icon)
struct TNMenuItem: Identifiable {
    let id = UUID(); let emoji: String; let label: String; let route: TNRoute?; let action: String?
    init(_ emoji: String, _ label: String, route: TNRoute? = nil, action: String? = nil) {
        self.emoji = emoji; self.label = label; self.route = route; self.action = action
    }
}
let TN_MENU: [TNMenuItem] = [
    TNMenuItem("🧘", "Tu Luyện", action: "meditate"),
    TNMenuItem("⚡", "Đột Phá", action: "breakthrough"),
    TNMenuItem("👹", "Boss/Phụ Bản", route: .boss),
    TNMenuItem("🏆", "Đấu Đài", route: .arena),
    TNMenuItem("⚔️", "PvP Xếp Hạng", route: .pvp),
    TNMenuItem("📜", "Nhiệm Vụ", route: .quest),
    TNMenuItem("📖", "Cốt Truyện", route: .story),
    TNMenuItem("🔥", "Kỹ Năng", route: .skills),
    TNMenuItem("🎒", "Túi Đồ", route: .bag),
    TNMenuItem("📗", "Tâm Pháp", route: .tech),
    TNMenuItem("⚒️", "Chế Tạo", route: .forge),
    TNMenuItem("🛒", "Cửa Hàng", route: .shop),
    TNMenuItem("🏪", "Chợ", route: .market),
    TNMenuItem("🐾", "Thú Cưng", route: .pets),
    TNMenuItem("🐲", "Thú Cưỡi", route: .mount),
    TNMenuItem("👗", "Thời Trang", route: .fashion),
    TNMenuItem("💞", "Đạo Lữ", route: .spouse),
    TNMenuItem("🏯", "Bang Hội", route: .guild),
    TNMenuItem("📅", "Điểm Danh", route: .checkin),
    TNMenuItem("🏅", "Thành Tựu", route: .achieve),
    TNMenuItem("👑", "VIP", route: .vip),
    TNMenuItem("💰", "Nạp", route: .recharge),
    TNMenuItem("💬", "Thế Giới Chat", route: .chat),
    TNMenuItem("🖼️", "Nhân Vật", route: .codex),
]

struct TNWorldView: View {
    @ObservedObject var game: TNGame
    @Environment(\.dismiss) private var dismiss
    @State private var hero = CGPoint(x: TN_WORLD_SIZE / 2, y: TN_WORLD_SIZE / 2)
    @State private var joy = CGVector(dx: 0, dy: 0)
    @State private var faceLeft = false
    @State private var walking = false
    @State private var mobs: [TNWorldMob] = tnMakeMobs()
    @State private var showBattle = false
    @State private var targetIdx: Int? = nil
    @State private var toast: String?
    @State private var route: TNRoute?
    @State private var showMenu = false
    @State private var dlgNPC: TNWorldNPC?
    @State private var dlgText = ""
    @State private var castFX: String?
    @State private var bob = false
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let camX = min(max(hero.x, center.x), TN_WORLD_SIZE - center.x)
            let camY = min(max(hero.y, center.y), TN_WORLD_SIZE - center.y)
            ZStack(alignment: .topLeading) {
                worldLayer
                    .frame(width: TN_WORLD_SIZE, height: TN_WORLD_SIZE)
                    .offset(x: center.x - camX, y: center.y - camY)

                // Hiệu ứng tung chiêu giữa màn khi đánh
                if let castFX {
                    Text(castFX).font(.system(size: 130))
                        .position(x: center.x, y: center.y - 30)
                        .transition(.scale.combined(with: .opacity)).allowsHitTesting(false)
                        .shadow(color: .orange, radius: 20)
                }

                // ===== HUD game =====
                VStack(spacing: 0) {
                    hudBar
                    Spacer()
                    HStack(alignment: .bottom) {
                        TNJoystick(vec: $joy)
                        Spacer()
                        actionButtons
                    }
                    .padding(.horizontal, 22).padding(.bottom, dlgNPC == nil ? 30 : 150)
                }
                // Cột icon chức năng bên phải
                sideIcons.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                // Toast thông báo
                if let toast {
                    Text(toast).font(.footnote.bold()).foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: geo.size.width - 80)
                        .position(x: center.x, y: geo.size.height * 0.28)
                        .transition(.opacity)
                }
                // Hộp thoại NPC (gõ chữ + âm thanh)
                if let npc = dlgNPC {
                    dialogBox(npc).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                // Bảng chức năng (thay cho menu nút cũ)
                if showMenu { menuPanel(geo) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .background(Color(red: 0.13, green: 0.2, blue: 0.13))
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in step() }
        .onAppear { withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { bob = true } }
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: mobEnemy(), storyMode: false) { won in
                if won, let i = targetIdx, mobs.indices.contains(i) {
                    mobs[i].alive = false
                    mobs[i].respawnAt = Date().addingTimeInterval(12)
                    TNSound.win()
                    flash("🎉 Hạ gục \(mobs[i].name)! Nhận linh thạch & EXP.")
                }
                targetIdx = nil
            }
        }
        .sheet(item: $route) { r in routeView(r) }
    }

    // ===== Lớp thế giới =====
    private var worldLayer: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red:0.16,green:0.28,blue:0.16), Color(red:0.10,green:0.18,blue:0.12)],
                           startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color(red:0.2,green:0.35,blue:0.5).opacity(0.5))
                .frame(width: 520, height: 220).position(x: 500, y: 1600)
            Ellipse().fill(Color(red:0.3,green:0.28,blue:0.18).opacity(0.5))
                .frame(width: 900, height: 120).position(x: 1200, y: 1200)
            ForEach(TN_DECOR) { d in
                Text(d.emoji).font(.system(size: d.size)).position(d.pos).allowsHitTesting(false)
            }
            ForEach(TN_WORLD_NPCS) { npc in
                VStack(spacing: 1) {
                    Text("💬").font(.system(size: 14)).opacity(nearNPC(npc) ? 1 : 0.35)
                    Text(npc.emoji).font(.system(size: 40))
                    Text(npc.name).font(.system(size: 10, weight: .bold)).foregroundStyle(.yellow)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(.black.opacity(0.5), in: Capsule())
                }.position(npc.pos).allowsHitTesting(false)
            }
            ForEach(mobs) { m in
                if m.alive {
                    VStack(spacing: 1) {
                        Text(m.emoji).font(.system(size: 38))
                            .scaleEffect(nearMob(m) ? 1.15 : 1.0)
                            .shadow(color: nearMob(m) ? .red : .clear, radius: 8)
                        Text(m.name).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 4).background(.red.opacity(0.5), in: Capsule())
                    }.position(m.pos).allowsHitTesting(false)
                }
            }
            heroSprite.position(hero)
        }
    }

    private var heroSprite: some View {
        VStack(spacing: 2) {
            Text(game.s.name).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.5)).frame(width: 46, height: 5)
                Capsule().fill(.green).frame(width: 46 * CGFloat(Double(game.s.hp) / Double(max(1, game.s.hpMax))), height: 5)
            }
            ZStack {
                Circle().fill(RadialGradient(colors: [tnSkin(game.s.skin).colors.first!.opacity(0.7), .clear], center: .center, startRadius: 0, endRadius: 34))
                    .frame(width: 64, height: 64)
                if let ui = UIImage(named: "tn_vuonglam") {
                    Image(uiImage: ui).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                } else {
                    Circle().fill(LinearGradient(colors: tnSkin(game.s.skin).colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 46, height: 46).overlay(Text("🥋").font(.system(size: 24)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                }
            }
            .scaleEffect(x: faceLeft ? -1 : 1, y: 1)
            .offset(y: walking && bob ? -3 : 0)
            Ellipse().fill(.black.opacity(0.3)).frame(width: 34, height: 9)
        }
    }

    private var hudBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
                    .padding(9).background(.black.opacity(0.45), in: Circle())
            }.buttonStyle(TNPress(glow: .white))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(game.s.name).font(.caption.bold()).foregroundStyle(.white)
                    Text("Lv.\(game.s.level)").font(.caption2.bold()).foregroundStyle(.yellow)
                    Text(game.s.realmEnum.name).font(.caption2).foregroundStyle(game.s.realmEnum.color)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5)).frame(width: 150, height: 8)
                    Capsule().fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 150 * CGFloat(Double(game.s.hp) / Double(max(1, game.s.hpMax))), height: 8)
                }
            }
            Spacer()
            Text("💎 \(game.s.linhThach)").font(.caption.bold()).foregroundStyle(.cyan)
                .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.horizontal, 14).padding(.top, 52)
    }

    // Cột icon chức năng nhanh bên phải + nút Menu
    private var sideIcons: some View {
        VStack(spacing: 12) {
            iconBtn("☰", "Menu", .orange) { TNSound.tap(); withAnimation(.spring(response: 0.3)) { showMenu = true } }
            iconBtn("📜", "N.Vụ", .green) { route = .quest }
            iconBtn("🎒", "Túi", .yellow) { route = .bag }
            iconBtn("🔥", "Skill", .red) { route = .skills }
            iconBtn("👹", "Boss", .purple) { route = .boss }
        }
        .padding(.trailing, 12).padding(.top, 150)
    }
    private func iconBtn(_ emoji: String, _ label: String, _ color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 1) {
                Text(emoji).font(.system(size: 22))
                Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
            .background(color.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.7), lineWidth: 1))
        }.buttonStyle(TNPress(glow: color))
    }

    @ViewBuilder private var actionButtons: some View {
        VStack(spacing: 12) {
            if let npc = nearestNPC(), dlgNPC == nil {
                Button { talk(npc) } label: {
                    VStack(spacing: 2) { Text("💬").font(.system(size: 24)); Text("Nói").font(.system(size: 9, weight: .bold)) }
                        .foregroundStyle(.white).frame(width: 64, height: 64)
                        .background(.blue, in: Circle()).shadow(color: .blue, radius: 8)
                }.buttonStyle(TNPress(glow: .blue))
            }
            if nearestMob() != nil {
                Button { attack() } label: {
                    VStack(spacing: 2) { Text("⚔️").font(.system(size: 28)); Text("Đánh").font(.system(size: 10, weight: .bold)) }
                        .foregroundStyle(.white).frame(width: 84, height: 84)
                        .background(LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom), in: Circle())
                        .shadow(color: .red, radius: 10)
                }.buttonStyle(TNPress(glow: .red, silent: true))
            }
        }
    }

    // Hộp thoại NPC kiểu RPG (chữ gõ dần + âm thanh)
    private func dialogBox(_ npc: TNWorldNPC) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Text(npc.emoji).font(.system(size: 46))
                    .frame(width: 64, height: 64).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(npc.name).font(.subheadline.bold()).foregroundStyle(.yellow)
                    Text(dlgText).font(.callout).foregroundStyle(.white)
                    HStack {
                        Spacer()
                        if let r = npcRoute(npc) {
                            Button("Vào ▶") { TNSound.tap(); dlgNPC = nil; route = r }
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6).background(.blue, in: Capsule())
                        }
                        Button("Đóng") { dlgNPC = nil }
                            .font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.15), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.yellow.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }

    // Bảng chức năng game (icon grid) — thay cho danh sách nút cũ
    private func menuPanel(_ geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { withAnimation { showMenu = false } }
            VStack(spacing: 12) {
                HStack {
                    Text("☰ CHỨC NĂNG").font(.headline.bold()).foregroundStyle(.yellow)
                    Spacer()
                    Button { withAnimation { showMenu = false } } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding(8).background(.white.opacity(0.15), in: Circle())
                    }
                }.padding(.horizontal, 4)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                        ForEach(TN_MENU) { it in
                            if !(it.action == "breakthrough" && !game.s.canBreakthrough) {
                                Button { tapMenu(it) } label: {
                                    VStack(spacing: 4) {
                                        Text(it.emoji).font(.system(size: 30))
                                        Text(it.label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                            .multilineTextAlignment(.center).lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 74)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) {
                                        if it.route == .achieve && game.pendingAchievements > 0 {
                                            Text("\(game.pendingAchievements)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                                .padding(4).background(.red, in: Circle()).offset(x: -4, y: 4)
                                        }
                                    }
                                }.buttonStyle(TNPress(glow: .yellow))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 460, maxHeight: geo.size.height * 0.7)
            .background(Color(red: 0.08, green: 0.09, blue: 0.15), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.yellow.opacity(0.3), lineWidth: 1))
            .padding(24)
        }
        .transition(.opacity)
    }
    private func tapMenu(_ it: TNMenuItem) {
        TNSound.tap()
        withAnimation { showMenu = false }
        if let r = it.route { route = r; return }
        switch it.action {
        case "meditate": game.meditate(); TNSound.coin(); flash("🧘 Thiền định — tu vi +\(max(6, game.s.expMax/12))")
        case "breakthrough": TNSound.level(); flash(game.breakthrough())
        default: break
        }
    }

    // Điểm đến từng chức năng
    @ViewBuilder private func routeView(_ r: TNRoute) -> some View {
        switch r {
        case .quest:  wrap("Nhiệm Vụ") { TNQuestView(game: game) }
        case .story:  wrap("Cốt Truyện") { TNStoryView(game: game) }
        case .skills: wrap("Kỹ Năng") { TNSkillsView(game: game) }
        case .shop:   wrap("Cửa Hàng") { TNShopView(game: game) }
        case .map:    TNMapView(game: game)
        case .pets:   TNPetView(game: game)
        case .fashion: TNFashionView(game: game)
        case .guild:  TNGuildView(game: game)
        case .pvp:    TNPvPView(game: game)
        case .spouse: TNSpouseView(game: game)
        case .mount:  TNMountView(game: game)
        case .recharge: TNRechargeView(game: game)
        case .vip:    TNVipView(game: game)
        case .achieve: TNAchieveView(game: game)
        case .boss:   TNBossView(game: game)
        case .tech:   TNTechView(game: game)
        case .checkin: TNCheckinView(game: game)
        case .chat:   TNChatView(game: game)
        case .market: TNMarketView(game: game)
        case .forge:  TNForgeView(game: game)
        case .arena:  TNArenaView(game: game)
        case .codex:  TNCharactersView()
        case .bag:    TNBagView(game: game)
        }
    }
    @ViewBuilder private func wrap<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { route = nil } } }
        }
        .preferredColorScheme(.dark)
    }

    // ===== Logic =====
    private func step() {
        guard !showBattle, dlgNPC == nil, !showMenu else { walking = false; return }
        let speed: CGFloat = 5.0
        if abs(joy.dx) > 0.05 || abs(joy.dy) > 0.05 {
            walking = true
            if joy.dx < -0.1 { faceLeft = true } else if joy.dx > 0.1 { faceLeft = false }
            var nx = hero.x + joy.dx * speed
            var ny = hero.y + joy.dy * speed
            nx = min(max(50, nx), TN_WORLD_SIZE - 50)
            ny = min(max(50, ny), TN_WORLD_SIZE - 50)
            hero = CGPoint(x: nx, y: ny)
        } else {
            walking = false
        }
        let now = Date()
        for i in mobs.indices where !mobs[i].alive {
            if let t = mobs[i].respawnAt, now >= t { mobs[i].alive = true; mobs[i].respawnAt = nil }
        }
    }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private func nearMob(_ m: TNWorldMob) -> Bool { m.alive && dist(m.pos, hero) < 95 }
    private func nearNPC(_ n: TNWorldNPC) -> Bool { dist(n.pos, hero) < 95 }
    private func nearestMob() -> Int? {
        var best: Int? = nil; var bd: CGFloat = 95
        for (i, m) in mobs.enumerated() where m.alive {
            let d = dist(m.pos, hero); if d < bd { bd = d; best = i }
        }
        return best
    }
    private func nearestNPC() -> TNWorldNPC? {
        TN_WORLD_NPCS.filter { dist($0.pos, hero) < 95 }.min { dist($0.pos, hero) < dist($1.pos, hero) }
    }
    private func npcRoute(_ npc: TNWorldNPC) -> TNRoute? {
        switch npc.action { case "quest": return .quest; case "market": return .market; case "forge": return .forge; default: return nil }
    }
    private func attack() {
        guard let i = nearestMob() else { return }
        targetIdx = i
        TNHaptic.hit(.heavy); TNSound.cast()
        // Hiệu ứng tung chiêu chớp giữa màn rồi vào trận
        withAnimation(.easeOut(duration: 0.2)) { castFX = "⚔️" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { castFX = nil }
            showBattle = true
        }
    }
    // NPC nói: gõ chữ dần + âm thanh nói
    private func talk(_ npc: TNWorldNPC) {
        TNHaptic.hit(.light); TNSound.talk()
        dlgNPC = npc; dlgText = ""
        typeNext(1, npc)
    }
    private func typeNext(_ i: Int, _ npc: TNWorldNPC) {
        guard dlgNPC?.id == npc.id else { return }
        let chars = Array(npc.line)
        if i <= chars.count {
            dlgText = String(chars.prefix(i))
            if i % 2 == 0 { TNSound.talk() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { typeNext(i + 1, npc) }
        }
    }
    private func mobEnemy() -> TNEnemy {
        let m = targetIdx.flatMap { mobs.indices.contains($0) ? mobs[$0] : nil }
        let lvl = Double(game.s.realm * 9 + game.s.stage + game.s.level / 5)
        let hp = Int((80 + lvl * 85) * Double.random(in: 0.9...1.2))
        return TNEnemy(name: m?.name ?? "Yêu Thú", emoji: m?.emoji ?? "🐺", hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * 0.55), def: Int(Double(game.s.def) * 0.55),
                       reward: Int(30 + lvl * 12), exp: Int(25 + lvl * 15))
    }
    private func flash(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { withAnimation { if toast == m { toast = nil } } }
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
// MARK: - Thư Viện Nhân Vật (Codex) — 38 nhân vật Tiên Nghịch đầy đủ lore
struct TNCodexChar: Identifiable {
    let id: String; let name: String; let cat: String; let catName: String
    let desc: String; let quote: String; let element: String; let rarity: String; let affinity: String
}
func tnAffStyle(_ a: String) -> (emoji: String, color: Color) {
    switch a {
    case "fire":      return ("🔥", .red)
    case "ice":       return ("❄️", .cyan)
    case "nature":    return ("🌿", .green)
    case "cosmos":    return ("☯️", .indigo)
    case "dark":      return ("💀", .purple)
    case "gold":      return ("🛡️", .orange)
    case "light":     return ("☀️", .yellow)
    case "wind":      return ("🌪️", .teal)
    case "lotus":     return ("🪷", .pink)
    default:           return ("⚡", Color(red: 1, green: 0.85, blue: 0.2))  // lightning
    }
}
let TN_CODEX_CATS: [(String, String)] = [
    ("ALL", "Tất cả"), ("MAIN", "Nhân Vật Chính"), ("ELITE", "Thiên Kiêu"),
    ("TOP", "Cường Giả Hàng Đầu"), ("MAIDEN", "Thánh Nữ"), ("BEAST", "Linh Thú & Yêu Thú"),
]
let TN_CODEX: [TNCodexChar] = [
    TNCodexChar(id: "vuong-lam", name: "Vương Lâm", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Tư chất bình thường, ý chí nghịch thiên. Đi con đường Nghịch Thiên đầy máu lôi kiếm.", quote: "Thuận thiên dã hảo, nghịch thiên dã bãi, chung quy bất quá thị nhất tràng chấp niệm.", element: "Lôi hệ tàn khốc / Sát phạt kiến đạo", rarity: "Chí Cao Thần Cấp", affinity: "lightning"),
    TNCodexChar(id: "ly-mong-dao", name: "Lý Mộng Dao", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Nữ chính thần bí, linh căn tuyệt đỉnh, thanh thuần thoát tục nhưng kiên định khôn cùng.", quote: "Thế gian nghìn vạn kiếp, thiếp nguyện bồi chàng vượt thiên địa hoang vu.", element: "Băng Tịnh hệ / Bạch Liên linh khí", rarity: "Tuyệt Thế Tiên Thể", affinity: "lotus"),
    TNCodexChar(id: "co-than", name: "Cổ Thần", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Thiên tài trẻ tuổi xuất chúng, kiêu ngạo vô song, khí chất vương giả hiếm ai bì kịp.", quote: "Cửu thiên thập địa, vạn tộc tranh phong, duy ngã độc tôn!", element: "Cổ Thần Thể / Kim Thổ Thần khí", rarity: "Huyền Thoại", affinity: "gold"),
    TNCodexChar(id: "tu-vo-tran", name: "Tư Vô Trần", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Tiên tôn cường giả cực độ uy nghiêm, thực lực thâm tàng bất lộ, hành tung xuất thần nhập hóa.", quote: "Dưới bóng tối của ta, các ngươi bất quá chỉ là bụi bặm hạt cát.", element: "Thái Cực Tinh Không / Vô cực khí quy luật", rarity: "Tiên Tôn Thượng Cấp", affinity: "cosmos"),
    TNCodexChar(id: "an-huyen", name: "An Huyền", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Ma Tu tối thượng, tâm cơ vô song, tà ác thâm hiểm và cực đoan mưu mô.", quote: "Chính tà chỉ là góc nhìn, người thắng mới nắm giữ chân lý vĩnh hằng.", element: "Huyền Ma hệ / U Hồn vạn trượng", rarity: "Cực Ma Đại Thừa", affinity: "dark"),
    TNCodexChar(id: "trinh-hao", name: "Trình Hạo", cat: "MAIN", catName: "Nhân Vật Chính", desc: "Thiên kiêu phong lưu khoáng đạt, tự cao tự đại, luôn mang thần thái nhẹ nhàng bay bổng.", quote: "Bất tử bất diệt cũng không sướng bằng một bầu linh tửu tiếu ngạo giang hồ.", element: "Phong Thần kiếm ý / Hư không dực", rarity: "Đế Tử Kiếp", affinity: "wind"),
    TNCodexChar(id: "do-thanh-y", name: "Đỗ Thanh Y", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Linh động, thông minh, tính khí tinh quái, tinh nghịch vô lường.", quote: "Đừng để bị lừa bởi khuôn mặt đáng yêu này nhé!", element: "Thảo mộc linh căn / Sinh cơ cửu thiên", rarity: "Huyền Cơ Cấp", affinity: "nature"),
    TNCodexChar(id: "diep-dong", name: "Diệp Động", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Cao ngạo lạnh lùng, trốn ẩn nơi tiên sơn, tu vi đỉnh phong.", quote: "Kiếm xuất quỷ thần kinh, ai muốn thử một kiếm của ta?", element: "Băng Linh Thể / Hàn Kiếm vô song", rarity: "Thiên Giao Cấp", affinity: "ice"),
    TNCodexChar(id: "muc-tran", name: "Mục Trần", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Trưởng lão trẻ uy vũ, Nguyên Anh Hậu kỳ danh chấn bát phương.", quote: "Dám can gián đại trận tông môn của ta, tru sát vô xá!", element: "Lôi Hỏa Chân Nguyên / Thần Ấn đại trận", rarity: "Đại Thừa Bán Bộ", affinity: "fire"),
    TNCodexChar(id: "tu-linh", name: "Tử Linh", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Yêu dã, quyến rũ cực độ nhưng ẩn chứa nguy hiểm trí mạng.", quote: "Độc dược ngọt ngào nhất chính là nụ cười của ta.", element: "Mị Ảnh Thần thông / Chu Sa độc cổ", rarity: "Yêu Cơ Thượng Cấp", affinity: "dark"),
    TNCodexChar(id: "thanh-van-tu", name: "Thanh Vân Tử", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Tiên tôn đạo mạo hiền từ, đầy trí tuệ nhân sinh cổ xưa.", quote: "Mọi việc trên đời đều là cơ duyên, chớ cưỡng cầu gượng ép.", element: "Thái cực âm dương / Trận đồ bát quái", rarity: "Độ Kiếp Thần Tăng", affinity: "cosmos"),
    TNCodexChar(id: "tu-han", name: "Tư Hàn", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Kiêu ngạo và quyết đoán, thiên tài tu luyện vạn năm khó gặp.", quote: "Kẻ yếu không có tư cách đàm phán với ta.", element: "Cuồng Lôi thần văn / Đao ảnh phá không", rarity: "Thánh Chủ Kỳ", affinity: "lightning"),
    TNCodexChar(id: "nguyet-nhi", name: "Nguyệt Nhi", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Hiền lành, nhân hậu, đại diện cho bản tính thuần khiết chân chất.", quote: "Hy vọng linh lực của ta có thể chữa lành vết thương cho huynh.", element: "Thần quang trị liệu / Nguyệt ảnh thánh thể", rarity: "Thánh Nữ Tiên Khí", affinity: "light"),
    TNCodexChar(id: "lam-thien", name: "Lâm Thiên", cat: "ELITE", catName: "Thiên Kiêu & Cường Giả", desc: "Thiên tài kiếm đạo lạnh lùng, ý chí kiên định như thiết thạch.", quote: "Tâm trung vô kiếm, nhân kiếm hợp nhất.", element: "Vô Ảnh thần kiếm / Toàn phong kiếm trận", rarity: "Kiếm Tôn Kỳ", affinity: "wind"),
    TNCodexChar(id: "thien-dao", name: "Thiên Đạo", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Quy tắc chí cao vô thượng của thiên địa, thần bí cực đoan, đầy uy nghiêm tột bực.", quote: "Trời ban thì được, trời phạt thì phải nhận.", element: "Vũ trụ hỗn độn / Bản nguyên quy luật", rarity: "Hỗn Độn Chí Cao", affinity: "cosmos"),
    TNCodexChar(id: "dai-truong-lao", name: "Đại Trưởng Lão", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Tông môn Đại trưởng lão đức cao vọng trọng, thủ hộ giả của tông môn tông mạch vạn năm.", quote: "Vì tông môn, thân già này dẫu thịt nát xương tan cũng không tiếc.", element: "Phật Quang hộ thể / Kim cang cốt nhục", rarity: "Đại Thừa Đỉnh Phong", affinity: "gold"),
    TNCodexChar(id: "la-sat", name: "La Sát", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Ma tu chiến thần khát máu, tàn bạo, vô tình không thèm thương tiếc bất kỳ sinh linh nào.", quote: "Thần cản sát thần, Phật cản sát Phật, máu nhuộm cửu thiên!", element: "Huyết Ma đao pháp / Tu la huyết diễm", rarity: "Huyết Hải Chiến Thần", affinity: "dark"),
    TNCodexChar(id: "thien-hoa-ton-gia", name: "Thiên Hỏa Tôn Giả", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Cường giả hỏa đạo cực đoan, tính khí nóng nảy, bộc trực, thẳng tính như lửa thiêu.", quote: "Một ngọn linh hỏa của lão phu có thể đốt trụi cả một tinh cầu!", element: "Thao Thiết chân hỏa / Hỏa Vân đại thần thông", rarity: "Đạo Tổ Cấp", affinity: "fire"),
    TNCodexChar(id: "hang-ma", name: "Hàng Ma", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Ma tu đại năng thiện chiến, bạo liệt cực độ.", quote: "Càng điên cuồng, sức mạnh của ta càng không giới hạn.", element: "Cửu u ma sương / Ma khí xung thiên", rarity: "Đại Ma Đầu", affinity: "dark"),
    TNCodexChar(id: "thai-so", name: "Thái Sơ", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Lão tổ tông môn cổ xưa, thực lực sâu sắc khôn lường.", quote: "Mấy vạn năm trôi qua nhanh như một giấc mộng phù du.", element: "Hỗn Độn Nguyên Khí / Tinh tú thiên quang", rarity: "Thái Thượng Thần Tôn", affinity: "gold"),
    TNCodexChar(id: "bach-y", name: "Bạch Y", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Sát thủ bí ẩn lạnh như băng tuyết, một nhát trúng ngay tim địch.", quote: "Ngươi sẽ không cảm nhận được đau đớn, vì kiếm của ta quá nhanh.", element: "Băng phách huyền trâm / U ảnh phi thiên", rarity: "Ám Ảnh Vô Song", affinity: "ice"),
    TNCodexChar(id: "hong-diep", name: "Hồng Diệp", cat: "TOP", catName: "Cường Giả Hàng Đầu", desc: "Yêu tộc công chúa kiêu sa, mạnh mẽ, thống lĩnh ngàn vạn yêu chúng.", quote: "Thần dân của ta sẽ xéo nát lãnh địa loài người các ngươi.", element: "Huyết tộc chân hỏa / Yêu đan huyết quang", rarity: "Yêu Đế Huyết Thống", affinity: "fire"),
    TNCodexChar(id: "phong-lan", name: "Phong Lan", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Tùy tùng trung thành của Vương Lâm, tính cách lạnh lùng, can trường.", quote: "Mệnh của Phong Lan từ lâu đã thuộc về chủ thượng.", element: "Lôi ảnh phi kiếm / Ám lôi phi hành", rarity: "Cực Hạn Kiếp", affinity: "lightning"),
    TNCodexChar(id: "tu-dien-ma-nu", name: "Tử Điện Ma Nữ", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Ma tộc mỹ nhân độc ác, xảo quyệt khôn lường.", quote: "Nam nhân trên đời càng đẹp đẽ càng thích hợp làm tế phẩm cho ma thần.", element: "Tử điện u minh / Độc tà âm linh", rarity: "Vạn Ma Diễm", affinity: "dark"),
    TNCodexChar(id: "thien-nguyet", name: "Thiên Nguyệt", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Thánh nữ mang khí chất bí ẩn, khó đoán, sở hữu thiên tai âm dương thiên sinh.", quote: "Thế sự mịt mờ, chiêm tinh thiên mệnh định sẵn thắng thua.", element: "Nguyệt hà huyền không / Tinh hệ thiên tinh", rarity: "Đạo Tiên Cấp", affinity: "cosmos"),
    TNCodexChar(id: "than-hon-gia", name: "Thần Hồn Gia", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Cường giả luyện hồn có âm khí thâm trầm, tính quỷ dị khó lường.", quote: "Vạn quỷ gầm thét, thần hồn câu diệt!", element: "Vạn linh ngự hồn / Cửu u tà trảo", rarity: "Luyện Hồn Sư Cực Phẩm", affinity: "dark"),
    TNCodexChar(id: "hac-y-nuong", name: "Hắc Y Nương", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Sát thủ thần bí, tính độc lập cực cao, cô độc một mình bước đi trên con đường máu.", quote: "Bóng đêm chính là lớp giáp tốt nhất của ta.", element: "Hắc ám nguyên khí / Ảnh độ pháp", rarity: "U Ám Thần Kiếp", affinity: "dark"),
    TNCodexChar(id: "lieu-nhu-yen", name: "Liễu Như Yến", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Đan đạo thiên tài ôn nhu, thông minh dị thường, thánh thiện.", quote: "Một đan cứu vạn người, một đan diệt vạn ma.", element: "Hồi sinh thần lực / Đan cốt thánh linh", rarity: "Đan Thánh Truyền Nhân", affinity: "nature"),
    TNCodexChar(id: "moc-dao", name: "Mộc Dao", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Y thuật cao siêu bậc nhất tu chân giới, tâm địa từ tâm, hiền dịu vô ngần.", quote: "Cứu người là bản phận, bất kể người phàm hay tiên nhân.", element: "Bích ngọc sinh cơ / Cam lộ cứu độ", rarity: "Dược Tiên", affinity: "nature"),
    TNCodexChar(id: "dao-dao", name: "Dao Dao", cat: "MAIDEN", catName: "Thánh Nữ / Nữ Cường", desc: "Linh thú hóa hình ngây thơ, tinh nghịch nhưng cực kỳ đáng yêu.", quote: "Chủ nhân ơi, Dao Dao muốn ăn đại bồi nguyên đan!", element: "Yêu linh quang mang / Khinh vân bộ pháp", rarity: "Linh Hồ Khải Huyền", affinity: "light"),
    TNCodexChar(id: "tieu-huyen", name: "Tiểu Huyền", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Linh thú nhỏ bé đồng hành tinh nghịch, đáng yêu khôn tả.", quote: "Graoo! Ta là siêu cấp thần thú đó nghe!", element: "Tinh hải vân lôi / Ngân hà huyễn ảnh", rarity: "Cổ Thần Thú Thể", affinity: "light"),
    TNCodexChar(id: "thanh-long", name: "Thanh Long", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú viễn cổ uy nghiêm, dũng mãnh, hô mưa gọi gió chấn động một phương.", quote: "Ngao! Long uy hiển hách, phàm nhân run rẩy đi!", element: "Lôi long phong bạo / Thanh khí hóa tinh", rarity: "Thánh Thú Viễn Cổ", affinity: "wind"),
    TNCodexChar(id: "hoa-phuong", name: "Hỏa Phượng", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú mang lửa bất tử rực rỡ, mang niềm kiêu hãnh bất khuất.", quote: "Niết bàn tái sinh, hỏa thiêu tam thiên thế giới!", element: "Bất Diệt Chu Tước diễm / Hỏa dực linh đan", rarity: "Thánh Thú Viễn Cổ", affinity: "fire"),
    TNCodexChar(id: "huyen-vu", name: "Huyền Vũ", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú của phòng ngự, trầm ổn, kiên cố không thể phá vỡ.", quote: "Chừng nào ta còn đứng đây, đừng hòng ai bước qua một bước.", element: "Thổ hoàng giáp vệ / Thạch bích vô cực", rarity: "Thánh Thú Viễn Cổ", affinity: "gold"),
    TNCodexChar(id: "bang-ho", name: "Băng Hổ", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú hung dữ, tàn bạo ẩn náu tại vùng cực hàn tuyết phủ vạn năm.", quote: "Hơi thở của ta sẽ đóng băng thần hồn của ngươi.", element: "Băng tinh cực đại / Tuyết sát diệt môn", rarity: "Cổ Thú Thượng Cổ", affinity: "ice"),
    TNCodexChar(id: "loi-ung", name: "Lôi Ưng", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú tốc độ có móng vuốt sắc bén, sấm sét dồn dập quanh thân.", quote: "Vút qua vạn dặm chỉ trong chớp mắt.", element: "Thiên lôi oanh tạc / Điện ảnh tung cánh", rarity: "Sấm Sét Điểu Vương", affinity: "lightning"),
    TNCodexChar(id: "hac-diep", name: "Hắc Điệp", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Linh thú cánh bướm thần bí có tốc độ phi phàm khôn tả.", quote: "Ảnh mờ hư huyễn, vô vết tích để lại.", element: "Điệp phấn huyễn ảnh / U ám hương thơm", rarity: "U Minh Linh Trùng", affinity: "dark"),
    TNCodexChar(id: "kim-o", name: "Kim Ô", cat: "BEAST", catName: "Linh Thú & Yêu Thú", desc: "Thần thú mặt trời cao quý vô ngần, thần tính bất phàm.", quote: "Thái dương ánh sáng chiêu rọi tà ma vô bóng.", element: "Kim Ô thần hỏa / Thái dương tiên quang", rarity: "Thiên Địa Cực Phẩm", affinity: "fire"),
]

struct TNCharactersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cat = "ALL"
    @State private var search = ""
    @State private var selected: TNCodexChar?
    private var filtered: [TNCodexChar] {
        TN_CODEX.filter { c in
            (cat == "ALL" || c.cat == cat) &&
            (search.isEmpty || c.name.localizedCaseInsensitiveContains(search) || c.element.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let ui = UIImage(named: "tn_roster") {
                        Image(uiImage: ui).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal).padding(.top, 8)
                    }
                    // Tìm kiếm
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                        TextField("Tìm tên nhân vật, pháp bảo…", text: $search)
                            .textFieldStyle(.plain).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule()).padding(.horizontal)
                    // Bộ lọc phân loại
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TN_CODEX_CATS, id: \.0) { c in
                                Button { withAnimation { cat = c.0 } } label: {
                                    Text(c.1).font(.caption.bold())
                                        .foregroundStyle(cat == c.0 ? .black : .white.opacity(0.8))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(cat == c.0 ? Color.yellow : Color.white.opacity(0.1), in: Capsule())
                                }
                            }
                        }.padding(.horizontal)
                    }
                    Text("\(filtered.count) nhân vật").font(.caption2).foregroundStyle(.white.opacity(0.5)).padding(.horizontal)
                    // Danh sách
                    ForEach(filtered) { c in
                        let st = tnAffStyle(c.affinity)
                        Button { selected = c } label: {
                            HStack(spacing: 12) {
                                Text(st.emoji).font(.system(size: 28)).frame(width: 52, height: 52)
                                    .background(st.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
                                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(st.color.opacity(0.5), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(c.name).font(.subheadline.bold()).foregroundStyle(.white)
                                        Text(c.catName.split(separator: " ").first.map(String.init) ?? "")
                                            .font(.system(size: 8, weight: .bold)).foregroundStyle(st.color)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(st.color.opacity(0.15), in: Capsule())
                                    }
                                    Text(c.desc).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("✦ \(c.rarity)").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(11).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 4)
            }
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.13), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Thư Viện Nhân Vật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
            .sheet(item: $selected) { c in TNCodexDetail(c: c) }
        }
    }
}

struct TNCodexDetail: View {
    let c: TNCodexChar
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let st = tnAffStyle(c.affinity)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [st.color.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 90))
                            .frame(width: 180, height: 180)
                        Circle().strokeBorder(AngularGradient(colors: [st.color, .white, st.color], center: .center), lineWidth: 3)
                            .frame(width: 130, height: 130)
                        Text(st.emoji).font(.system(size: 70))
                    }.padding(.top, 10)
                    Text(c.name).font(.title.bold()).foregroundStyle(.white)
                    Text(c.catName).font(.caption.bold()).foregroundStyle(st.color)
                        .padding(.horizontal, 12).padding(.vertical, 4).background(st.color.opacity(0.15), in: Capsule())
                    Text("“\(c.quote)”").font(.callout.italic()).foregroundStyle(.yellow.opacity(0.9))
                        .multilineTextAlignment(.center).padding(.horizontal)
                    VStack(spacing: 10) {
                        detailRow("📜 Mô tả", c.desc)
                        detailRow("⚡ Khí Hải / Linh lực", c.element)
                        detailRow("✦ Độ quý hiếm", c.rarity)
                    }
                    .padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.05, blue: 0.14), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle(c.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.subheadline).foregroundStyle(.white)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
