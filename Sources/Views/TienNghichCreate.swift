import SwiftUI
import UIKit
import AudioToolbox

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
        let ngoc = game.rollTienNgoc()   // 🔮 rơi Tiên Ngọc 30%
        game.save()
        cooldowns[q.0] = Date()
        let ngocMsg = ngoc > 0 ? " · 🔮 +\(ngoc) Tiên Ngọc!" : ""
        flash((up > 0 ? "🎉 LÊN CẤP \(game.s.level)! " : "✨ +\(q.3) EXP · 💎 +\(q.4)") + ngocMsg)
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
