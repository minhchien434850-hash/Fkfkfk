import SwiftUI
import UIKit
import AudioToolbox

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
