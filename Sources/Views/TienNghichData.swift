import SwiftUI
import UIKit
import AudioToolbox

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
