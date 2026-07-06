import SwiftUI
import UIKit
import AudioToolbox

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
        pushOnline()   // đồng bộ máy chủ (có tiết lưu)
    }

    // ===== ONLINE — đồng bộ tiến trình lên máy chủ + nạp tiền thật =====
    @Published var online = false
    @Published var walletVND = 0
    private var baseURL = ""
    private var authToken: String?
    private var lastPush = Date.distantPast

    func configureOnline(base: String, token: String?) {
        var b = base.trimmingCharacters(in: .whitespaces)
        if b.hasSuffix("/") { b.removeLast() }
        baseURL = b
        authToken = (token?.isEmpty == false) ? token : nil
        if !baseURL.isEmpty, authToken != nil { loadOnline() }
    }
    private func gameReq(_ path: String, _ method: String) -> URLRequest? {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else { return nil }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken { r.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
        return r
    }
    func loadOnline() {
        guard let req = gameReq("/game/tn/state", "GET") else { return }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let wallet = obj["wallet"] as? Int
            let saveStr = obj["data"] as? String
            Task { @MainActor in
                self.online = true
                if let wallet { self.walletVND = wallet }
                if let saveStr, let dd = saveStr.data(using: .utf8),
                   let v = try? JSONDecoder().decode(TNSave.self, from: dd), v.created, self.serverPreferred(v) {
                    self.s = v
                    if self.s.hp <= 0 || self.s.hp > self.s.hpMax { self.s.hp = self.s.hpMax }
                    if let d = try? JSONEncoder().encode(self.s) { UserDefaults.standard.set(d, forKey: self.key) }
                }
            }
        }.resume()
    }
    // Ưu tiên bản máy chủ nếu tiến trình xa hơn (tránh mất tiến trình khi đổi máy)
    private func serverPreferred(_ v: TNSave) -> Bool {
        if !s.created { return true }
        return (v.realm * 100 + v.level) > (s.realm * 100 + s.level)
    }
    func pushOnline(force: Bool = false) {
        guard authToken != nil, s.created else { return }
        if !force && Date().timeIntervalSince(lastPush) < 4 { return }
        lastPush = Date()
        guard var req = gameReq("/game/tn/state", "POST"),
              let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) else { return }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": str])
        URLSession.shared.dataTask(with: req).resume()
    }
    // Nạp linh thạch bằng TIỀN THẬT (trừ số dư ví trên máy chủ)
    func buyReal(_ package: String, _ done: @escaping (Bool, String) -> Void) {
        guard var req = gameReq("/game/tn/buy", "POST") else { done(false, "Cần đăng nhập tài khoản KENIOS."); return }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["package": package])
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let obj = (data != nil) ? ((try? JSONSerialization.jsonObject(with: data!)) as? [String: Any]) : nil
            let http = resp as? HTTPURLResponse
            let bad = (http != nil) && !(200..<300).contains(http!.statusCode)
            let detail = obj?["detail"] as? String
            let lt = obj?["linhThach"] as? Int
            let w = obj?["wallet"] as? Int
            let added = obj?["linhthach_added"] as? Int
            let hasData = data != nil
            Task { @MainActor in
                if !hasData { done(false, "Lỗi mạng, thử lại."); return }
                if bad { done(false, detail ?? "Nạp thất bại."); return }
                if let lt { self.s.linhThach = lt }
                if let w { self.walletVND = w }
                if let d = try? JSONEncoder().encode(self.s) { UserDefaults.standard.set(d, forKey: self.key) }
                done(true, "✅ Nạp thành công +\(added ?? 0) linh thạch!")
            }
        }.resume()
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
