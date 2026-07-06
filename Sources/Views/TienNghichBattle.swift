import SwiftUI
import UIKit
import AudioToolbox

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
                TNResultView(win: win, loot: game.lastLoot) {
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
    var loot = TNLoot()
    let onClose: () -> Void
    @State private var pop = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(win ? "🎉 CHIẾN THẮNG!" : "💀 THẤT BẠI").font(.largeTitle.bold())
                    .foregroundStyle(win ? .yellow : .red)
                    .scaleEffect(pop ? 1.0 : 0.6)
                if win {
                    Text("— CHIẾN LỢI PHẨM —").font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                    VStack(spacing: 8) {
                        lootRow("💎", "Linh thạch", loot.linhThach, .cyan)
                        lootRow("✨", "Tu vi", loot.exp, .orange)
                        if loot.tienNgoc > 0 {
                            lootRow("🔮", "Tiên Ngọc", loot.tienNgoc, Color(red:0.5,green:1,blue:0.7))
                                .shadow(color: Color(red:0.4,green:1,blue:0.6), radius: 8)
                        }
                        if loot.linhThao > 0 { lootRow("🌿", "Linh thảo", loot.linhThao, .green) }
                        if loot.khoangThach > 0 { lootRow("⛏️", "Khoáng thạch", loot.khoangThach, .brown) }
                    }
                    .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("Đạo hữu bại trận nhưng được cứu chữa,\nmáu đã hồi đầy. Luyện thêm rồi quay lại!")
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)).font(.footnote)
                }
                Button(action: onClose) {
                    Text("Trở về").font(.headline).foregroundStyle(.white)
                        .frame(width: 180).padding(.vertical, 12)
                        .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }.buttonStyle(TNPress(glow: .purple))
            }
            .padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 30)
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { pop = true } }
    }
    private func lootRow(_ emoji: String, _ name: String, _ amount: Int, _ color: Color) -> some View {
        HStack {
            Text(emoji).font(.title3)
            Text(name).foregroundStyle(.white.opacity(0.85)).font(.subheadline)
            Spacer()
            Text("+\(amount)").font(.subheadline.bold()).foregroundStyle(color)
        }.frame(width: 210)
    }
}
