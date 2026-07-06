import SwiftUI
import UIKit
import AudioToolbox

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

                    // Ví TIỀN THẬT (đồng bộ máy chủ) — nạp tiền vào ví qua VietQR ở mục Ví của app
                    HStack {
                        Image(systemName: "wallet.pass.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ví tiền: \(game.walletVND.formatted())đ").font(.subheadline.bold()).foregroundStyle(.green)
                            Text(game.online ? "Đã kết nối máy chủ — nạp gói dưới sẽ trừ ví tiền thật."
                                              : "Chưa đăng nhập — đăng nhập KENIOS để nạp tiền thật.")
                                .font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(12).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.green.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal)

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

                    Text("Nạp bằng TIỀN THẬT: trừ số dư Ví (nạp Ví qua VietQR ở mục Ví của app). Linh thạch dùng mua skin, thú cưng, thú cưỡi, đạo lữ, rèn trang bị…")
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
                    if let p = pending {
                        if game.online {
                            msg = "⏳ Đang xử lý…"
                            game.buyReal(p.id) { ok, m in msg = m; if ok { TNHaptic.success() } }
                        } else {
                            msg = game.recharge(p); TNHaptic.success()   // ngoại tuyến: nạp tạm khi chưa đăng nhập
                        }
                    }
                    pending = nil
                }
                Button("Huỷ", role: .cancel) { pending = nil }
            } message: {
                Text("Nạp gói \(pending?.name ?? "") — nhận \(( (pending?.linhThach ?? 0) + (pending?.bonus ?? 0) )) linh thạch.\(game.online ? " Sẽ trừ ví tiền thật." : "")")
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
