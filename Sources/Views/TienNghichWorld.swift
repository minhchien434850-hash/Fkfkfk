import SwiftUI
import UIKit
import AudioToolbox

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
    var elite = false        // quái Tinh Anh (mini-boss) — mạnh hơn, thưởng hậu, chắc rơi Tiên Ngọc
    var alive = true
    var respawnAt: Date? = nil
}
func tnMakeMobs() -> [TNWorldMob] {
    let kinds = [("Yêu Lang","🐺"),("Sơn Trư","🐗"),("Độc Xà","🐍"),("Hắc Hùng","🐻"),
                 ("Yêu Hồ","🦊"),("Độc Chu","🕷️"),("Huyết Bức","🦇"),("Thạch Quái","🗿")]
    let elites = [("Hắc Phong Yêu Vương","👹"),("Huyết Nhãn Ma Lang","🐺"),("Thượng Cổ Hung Thú","🦁")]
    var out: [TNWorldMob] = []
    var seed: UInt64 = 77777
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 100000) / 100000 }
    for i in 0..<16 {
        let x = 150 + rnd() * (TN_WORLD_SIZE - 300)
        let y = 150 + rnd() * (TN_WORLD_SIZE - 300)
        let k = kinds[i % kinds.count]
        out.append(TNWorldMob(pos: CGPoint(x: x, y: y), name: k.0, emoji: k.1))
    }
    // 3 quái Tinh Anh (mini-boss) rải rác
    for j in 0..<elites.count {
        let x = 250 + rnd() * (TN_WORLD_SIZE - 500)
        let y = 250 + rnd() * (TN_WORLD_SIZE - 500)
        out.append(TNWorldMob(pos: CGPoint(x: x, y: y), name: elites[j].0, emoji: elites[j].1, elite: true))
    }
    return out
}

// NPC thân thiện trong thế giới
struct TNWorldNPC: Identifiable {
    let id = UUID(); let pos: CGPoint; let name: String; let emoji: String; let line: String; let action: String
    var img: String? = nil    // ảnh chân dung thật (nếu có)
}
let TN_WORLD_NPCS: [TNWorldNPC] = [
    TNWorldNPC(pos: CGPoint(x: 1100, y: 1100), name: "Đại Trưởng Lão", emoji: "🧙", line: "Hậu bối, chăm chỉ tu luyện sẽ có ngày phi thăng!", action: "quest", img: "tnc_dai-truong-lao"),
    TNWorldNPC(pos: CGPoint(x: 700, y: 900), name: "Liễu Như Yến", emoji: "🧕", line: "Ghé xem hàng hoá & đan dược của ta chứ?", action: "market", img: "tnc_lieu-nhu-yen"),
    TNWorldNPC(pos: CGPoint(x: 1500, y: 800), name: "Thái Sơ", emoji: "🧔", line: "Trang bị tốt cần rèn giũa. Vào lò chứ?", action: "forge", img: "tnc_thai-so"),
]

// ============================ BẢN ĐỒ ĐỊA HÌNH (vẽ vector — nét ở mọi độ phân giải) ============================
// Vẽ 1 lần ra ảnh đệm để không phải vẽ lại mỗi khung khi di chuyển (mượt + nhẹ RAM).
struct TNTerrain: View {
    var quality: Int = 2
    @State private var img: Image?
    var body: some View {
        Group {
            if let img { img.resizable().interpolation(.medium) }
            else { Color(red: 0.16, green: 0.30, blue: 0.18) }
        }
        .onAppear { renderOnce() }
        .onChange(of: quality) { _ in renderOnce() }
    }
    private func renderOnce() {
        let px: CGFloat = 1100
        let renderer = ImageRenderer(content: TNTerrainCanvas(quality: quality).frame(width: px, height: px))
        renderer.scale = 1
        if let ui = renderer.uiImage { img = Image(uiImage: ui) }
    }
}
struct TNTerrainCanvas: View {
    var quality: Int = 2
    var body: some View {
        Canvas { ctx, size in
            let W = size.width
            // Nền cỏ
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red:0.20,green:0.42,blue:0.22),
                                                             Color(red:0.11,green:0.27,blue:0.15)]),
                                           startPoint: .zero, endPoint: CGPoint(x: W, y: W)))
            var seed: UInt64 = 12345
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 100000) / 100000 }
            // Mảng cỏ đậm tạo chiều sâu
            for _ in 0..<70 {
                let cx = rnd()*W, cy = rnd()*W, r = 30 + rnd()*80
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r*0.5, width: r*2, height: r)),
                         with: .color(Color(red:0.09,green:0.22,blue:0.12).opacity(0.35)))
            }
            // Lưới ô mờ
            var grid = Path(); let step: CGFloat = 130
            var gx: CGFloat = 0; while gx <= W { grid.move(to: CGPoint(x: gx, y: 0)); grid.addLine(to: CGPoint(x: gx, y: W)); gx += step }
            var gy: CGFloat = 0; while gy <= W { grid.move(to: CGPoint(x: 0, y: gy)); grid.addLine(to: CGPoint(x: W, y: gy)); gy += step }
            ctx.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 1)
            // Sông uốn lượn
            var river = Path()
            river.move(to: CGPoint(x: 180, y: 0))
            river.addCurve(to: CGPoint(x: 760, y: W), control1: CGPoint(x: 560, y: W*0.32), control2: CGPoint(x: 60, y: W*0.7))
            ctx.stroke(river, with: .linearGradient(Gradient(colors: [Color(red:0.25,green:0.52,blue:0.72), Color(red:0.14,green:0.34,blue:0.6)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: W, y: W)),
                       style: StrokeStyle(lineWidth: 95, lineCap: .round))
            ctx.stroke(river, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 30, lineCap: .round))
            // Đường mòn đất chữ thập
            var road = Path()
            road.move(to: CGPoint(x: 0, y: W*0.5)); road.addLine(to: CGPoint(x: W, y: W*0.5))
            road.move(to: CGPoint(x: W*0.52, y: 0)); road.addLine(to: CGPoint(x: W*0.52, y: W))
            ctx.stroke(road, with: .color(Color(red:0.44,green:0.35,blue:0.22).opacity(0.55)), style: StrokeStyle(lineWidth: 72, lineCap: .round))
            ctx.stroke(road, with: .color(Color(red:0.52,green:0.42,blue:0.28).opacity(0.4)), style: StrokeStyle(lineWidth: 20, lineCap: .round))
            // Dãy núi viền trên
            for i in 0..<9 {
                let mx = CGFloat(i)*W/9 + 20
                var m = Path()
                m.move(to: CGPoint(x: mx, y: 300)); m.addLine(to: CGPoint(x: mx+150, y: 300)); m.addLine(to: CGPoint(x: mx+75, y: 70)); m.closeSubpath()
                ctx.fill(m, with: .color(Color(red:0.28,green:0.3,blue:0.33).opacity(0.65)))
                var cap = Path(); cap.move(to: CGPoint(x: mx+52, y: 140)); cap.addLine(to: CGPoint(x: mx+98, y: 140)); cap.addLine(to: CGPoint(x: mx+75, y: 70)); cap.closeSubpath()
                ctx.fill(cap, with: .color(.white.opacity(0.55)))
            }
            // Cây cối (vector) — mật độ theo độ hoạ
            let q = max(0, min(2, quality))
            let treeCount = [45, 85, 140][q]
            seed = 24680
            for _ in 0..<treeCount {
                let tx = rnd()*W, ty = 340 + rnd()*(W-360), s = 15 + rnd()*16
                ctx.fill(Path(ellipseIn: CGRect(x: tx-s*0.75, y: ty+s*0.85, width: s*1.5, height: s*0.5)), with: .color(.black.opacity(0.18)))
                ctx.fill(Path(CGRect(x: tx-s*0.12, y: ty, width: s*0.24, height: s*0.95)), with: .color(Color(red:0.34,green:0.22,blue:0.12)))
                for c in [CGPoint(x: 0, y: -1), CGPoint(x: -0.62, y: -0.42), CGPoint(x: 0.62, y: -0.42)] {
                    let rr: CGFloat = (c.x == 0 ? 1.0 : 0.72) * s
                    ctx.fill(Path(ellipseIn: CGRect(x: tx + c.x*s - rr, y: ty + c.y*s - rr, width: rr*2, height: rr*2)),
                             with: .color(Color(red:0.15,green:0.4,blue:0.2)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: tx - s*0.4, y: ty - s*1.3, width: s*0.7, height: s*0.7)), with: .color(Color(red:0.22,green:0.5,blue:0.27).opacity(0.7)))
            }
            // Đá
            for _ in 0..<[14, 26, 40][q] {
                let rx = rnd()*W, ry = 340 + rnd()*(W-360), s = 12 + rnd()*18
                ctx.fill(Path(ellipseIn: CGRect(x: rx-s, y: ry-s*0.7, width: s*2, height: s*1.3)), with: .color(Color(red:0.4,green:0.4,blue:0.42)))
                ctx.fill(Path(ellipseIn: CGRect(x: rx-s*0.5, y: ry-s*0.7, width: s*1.2, height: s*0.7)), with: .color(.white.opacity(0.12)))
            }
            // Hoa
            for _ in 0..<[30, 70, 120][q] {
                let fx = rnd()*W, fy = 340 + rnd()*(W-360)
                let cols = [Color.pink, .yellow, .white, .purple, .orange]
                ctx.fill(Path(ellipseIn: CGRect(x: fx-3.5, y: fy-3.5, width: 7, height: 7)), with: .color(cols[Int(rnd()*5) % 5].opacity(0.85)))
            }
        }
    }
}

// Nhân vật vẽ vector (không dùng emoji hệ thống) — tiên nhân áo bào
struct TNHeroVector: View {
    var colors: [Color]
    var size: CGFloat = 46
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            // áo bào (thân)
            var robe = Path()
            robe.move(to: CGPoint(x: w*0.5, y: h*0.28))
            robe.addLine(to: CGPoint(x: w*0.82, y: h*0.95))
            robe.addLine(to: CGPoint(x: w*0.18, y: h*0.95))
            robe.closeSubpath()
            ctx.fill(robe, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)))
            // đai lưng
            ctx.fill(Path(CGRect(x: w*0.3, y: h*0.6, width: w*0.4, height: h*0.08)), with: .color(.yellow.opacity(0.8)))
            // đầu
            ctx.fill(Path(ellipseIn: CGRect(x: w*0.36, y: h*0.08, width: w*0.28, height: w*0.28)), with: .color(Color(red:0.98,green:0.85,blue:0.72)))
            // tóc
            var hair = Path(); hair.addArc(center: CGPoint(x: w*0.5, y: h*0.2), radius: w*0.16, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.fill(hair, with: .color(Color(red:0.15,green:0.12,blue:0.1)))
        }
        .frame(width: size, height: size)
    }
}

// Icon UI vẽ vector (không dùng emoji/hệ thống)
struct TNVIcon: View {
    let kind: String
    var color: Color = .white
    var size: CGFloat = 24
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let col = GraphicsContext.Shading.color(color)
            switch kind {
            case "menu":
                for i in 0..<3 {
                    let y = h*0.28 + CGFloat(i)*h*0.22
                    ctx.fill(Path(roundedRect: CGRect(x: w*0.18, y: y, width: w*0.64, height: h*0.1), cornerRadius: 2), with: col)
                }
            case "quest": // cuộn giấy
                ctx.stroke(Path(roundedRect: CGRect(x: w*0.22, y: h*0.15, width: w*0.56, height: h*0.7), cornerRadius: 4), with: col, lineWidth: 2)
                for i in 0..<3 { let y = h*0.32 + CGFloat(i)*h*0.16; ctx.stroke(Path { $0.move(to: CGPoint(x: w*0.32, y: y)); $0.addLine(to: CGPoint(x: w*0.68, y: y)) }, with: col, lineWidth: 1.5) }
            case "bag": // túi
                var p = Path(); p.move(to: CGPoint(x: w*0.25, y: h*0.4)); p.addLine(to: CGPoint(x: w*0.75, y: h*0.4)); p.addLine(to: CGPoint(x: w*0.82, y: h*0.85)); p.addLine(to: CGPoint(x: w*0.18, y: h*0.85)); p.closeSubpath()
                ctx.fill(p, with: col)
                ctx.stroke(Path { $0.addArc(center: CGPoint(x: w*0.5, y: h*0.4), radius: w*0.15, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: true) }, with: col, lineWidth: 2)
            case "skill": // ngọn lửa
                var f = Path(); f.move(to: CGPoint(x: w*0.5, y: h*0.12)); f.addQuadCurve(to: CGPoint(x: w*0.8, y: h*0.6), control: CGPoint(x: w*0.85, y: h*0.3)); f.addQuadCurve(to: CGPoint(x: w*0.5, y: h*0.9), control: CGPoint(x: w*0.75, y: h*0.9)); f.addQuadCurve(to: CGPoint(x: w*0.2, y: h*0.6), control: CGPoint(x: w*0.25, y: h*0.9)); f.addQuadCurve(to: CGPoint(x: w*0.5, y: h*0.12), control: CGPoint(x: w*0.15, y: h*0.3)); f.closeSubpath()
                ctx.fill(f, with: col)
            case "boss": // đầu lâu
                ctx.fill(Path(ellipseIn: CGRect(x: w*0.22, y: h*0.15, width: w*0.56, height: h*0.55)), with: col)
                ctx.fill(Path(CGRect(x: w*0.4, y: h*0.6, width: w*0.2, height: h*0.22)), with: col)
                ctx.fill(Path(ellipseIn: CGRect(x: w*0.32, y: h*0.32, width: w*0.12, height: h*0.14)), with: .color(.black))
                ctx.fill(Path(ellipseIn: CGRect(x: w*0.56, y: h*0.32, width: w*0.12, height: h*0.14)), with: .color(.black))
            case "back":
                ctx.stroke(Path { $0.move(to: CGPoint(x: w*0.62, y: h*0.2)); $0.addLine(to: CGPoint(x: w*0.32, y: h*0.5)); $0.addLine(to: CGPoint(x: w*0.62, y: h*0.8)) }, with: col, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            default:
                ctx.fill(Path(ellipseIn: CGRect(x: w*0.3, y: h*0.3, width: w*0.4, height: h*0.4)), with: col)
            }
        }
        .frame(width: size, height: size)
    }
}

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
    TNMenuItem("⚙️", "Đồ Hoạ", action: "gfx"),
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
    @State private var celebrate: String?
    @State private var shownLevel = -1
    @State private var shownRealm = -1
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let camX = min(max(hero.x, center.x), TN_WORLD_SIZE - center.x)
            let camY = min(max(hero.y, center.y), TN_WORLD_SIZE - center.y)
            ZStack(alignment: .topLeading) {
                // Bản đồ + thực thể — KẸP trong màn hình (không để khung 2200px làm tràn HUD)
                worldLayer
                    .frame(width: TN_WORLD_SIZE, height: TN_WORLD_SIZE)
                    .offset(x: center.x - camX, y: center.y - camY)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()

                // Hiệu ứng tung chiêu giữa màn khi đánh
                if let castFX {
                    Text(castFX).font(.system(size: 130))
                        .position(x: center.x, y: center.y - 30)
                        .transition(.scale.combined(with: .opacity)).allowsHitTesting(false)
                        .shadow(color: .orange, radius: 20)
                }

                // ===== HUD game (neo theo MÀN HÌNH) =====
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
                .frame(width: geo.size.width, height: geo.size.height)

                // Cột icon chức năng bên phải
                sideIcons.frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)

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
                // Hiệu ứng LÊN CẤP / ĐỘT PHÁ toàn màn
                if let celebrate {
                    VStack {
                        Text(celebrate)
                            .font(.system(size: 36, weight: .black, design: .serif))
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .white], startPoint: .leading, endPoint: .trailing))
                            .multilineTextAlignment(.center)
                            .shadow(color: .orange, radius: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.35).ignoresSafeArea())
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .background(Color(red: 0.13, green: 0.2, blue: 0.13))
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in step() }
        .onChange(of: game.s.level) { v in
            if v > shownLevel { shownLevel = v; showCelebrate("⭐ LÊN CẤP \(v)!") } else { shownLevel = v }
        }
        .onChange(of: game.s.realm) { v in
            if v > shownRealm { shownRealm = v; showCelebrate("⚡ ĐỘT PHÁ\n\(game.s.realmEnum.name)!") } else { shownRealm = v }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { bob = true }
            shownLevel = game.s.level; shownRealm = game.s.realm
        }
        .fullScreenCover(isPresented: $showBattle) {
            TNBattleView(game: game, enemy: mobEnemy(), storyMode: false) { won in
                if won, let i = targetIdx, mobs.indices.contains(i) {
                    let m = mobs[i]
                    mobs[i].alive = false
                    mobs[i].respawnAt = Date().addingTimeInterval(m.elite ? 45 : 12)
                    TNSound.win()
                    if m.elite {
                        // Tinh Anh: thưởng hậu — chắc chắn Tiên Ngọc + rơi trang bị
                        let bonus = Int.random(in: 3...6)
                        game.s.tienNgoc += bonus
                        let g = game.dropGear(minRarity: 2)
                        game.save()
                        flash("👑 Hạ Tinh Anh \(m.name)! 🔮 +\(bonus) Tiên Ngọc · 🎁 \(tnRarityName(g.rarity)) \(tnGearName(g))")
                    } else {
                        flash("🎉 Hạ gục \(m.name)! Nhận chiến lợi phẩm.")
                    }
                }
                targetIdx = nil
            }
        }
        .sheet(item: $route) { r in routeView(r) }
    }

    // ===== Lớp thế giới =====
    private var worldLayer: some View {
        ZStack(alignment: .topLeading) {
            // Bản đồ địa hình vector (cỏ, sông, đường, núi, cây, đá, hoa)
            TNTerrain(quality: game.s.gfx)
                .frame(width: TN_WORLD_SIZE, height: TN_WORLD_SIZE)
            ForEach(TN_WORLD_NPCS) { npc in
                VStack(spacing: 1) {
                    Text("💬").font(.system(size: 14)).opacity(nearNPC(npc) ? 1 : 0.35)
                    if let img = npc.img, let ui = UIImage(named: img) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle())
                            .overlay(Circle().strokeBorder(.yellow.opacity(0.8), lineWidth: 2))
                            .shadow(color: .yellow.opacity(nearNPC(npc) ? 0.7 : 0), radius: 8)
                    } else {
                        Text(npc.emoji).font(.system(size: 40))
                    }
                    Text(npc.name).font(.system(size: 10, weight: .bold)).foregroundStyle(.yellow)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(.black.opacity(0.5), in: Capsule())
                }.position(npc.pos).allowsHitTesting(false)
            }
            ForEach(mobs) { m in
                if m.alive {
                    VStack(spacing: 1) {
                        if m.elite { Text("👑").font(.system(size: 16)) }
                        Text(m.emoji).font(.system(size: m.elite ? 54 : 38))
                            .scaleEffect(nearMob(m) ? 1.15 : 1.0)
                            .shadow(color: m.elite ? .orange : (nearMob(m) ? .red : .clear), radius: m.elite ? 14 : 8)
                        Text(m.name).font(.system(size: m.elite ? 10 : 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background((m.elite ? Color.orange : Color.red).opacity(0.6), in: Capsule())
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
                if let ui = UIImage(named: "tnc_vuong-lam") ?? UIImage(named: "tn_vuonglam") {
                    // Ảnh chân dung thật KẸP với hào quang Canvas phía sau
                    Image(uiImage: ui).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                } else {
                    TNHeroVector(colors: tnSkin(game.s.skin).colors, size: 50)
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
                TNVIcon(kind: "back", color: .white, size: 20)
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
            Text("🔮 \(game.s.tienNgoc)").font(.caption.bold()).foregroundStyle(Color(red:0.5,green:1,blue:0.7))
                .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.45), in: Capsule())
            Text("💎 \(game.s.linhThach)").font(.caption.bold()).foregroundStyle(.cyan)
                .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.horizontal, 14).padding(.top, 52)
    }

    // Cột icon chức năng nhanh bên phải + nút Menu (icon VẼ VECTOR, không dùng emoji hệ thống)
    private var sideIcons: some View {
        VStack(spacing: 12) {
            iconBtn("menu", "Menu", .orange) { TNSound.tap(); withAnimation(.spring(response: 0.3)) { showMenu = true } }
            iconBtn("quest", "N.Vụ", .green) { route = .quest }
            iconBtn("bag", "Túi", .yellow) { route = .bag }
            iconBtn("skill", "Skill", .red) { route = .skills }
            iconBtn("boss", "Boss", .purple) { route = .boss }
        }
        .padding(.trailing, 12).padding(.top, 150)
    }
    private func iconBtn(_ kind: String, _ label: String, _ color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 2) {
                TNVIcon(kind: kind, color: .white, size: 24)
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
                Group {
                    if let img = npc.img, let ui = UIImage(named: img) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else { Text(npc.emoji).font(.system(size: 46)) }
                }
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.yellow.opacity(0.5), lineWidth: 1))
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
                // Tài nguyên + gợi ý chi phí đột phá
                HStack(spacing: 10) {
                    Text("💎 \(game.s.linhThach)").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("🔮 \(game.s.tienNgoc) Tiên Ngọc").font(.caption.bold()).foregroundStyle(Color(red:0.5,green:1,blue:0.7))
                    Spacer()
                    if game.breakthroughTienNgocCost > 0 {
                        Text("Đột phá kế: \(game.breakthroughTienNgocCost) 🔮").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
        case "gfx":
            game.s.gfx = (game.s.gfx + 1) % 3; game.save()
            flash("⚙️ Độ hoạ: \(["Thấp","Vừa","Cao"][game.s.gfx])")
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
        let elite = m?.elite ?? false
        let lvl = Double(game.s.realm * 9 + game.s.stage + game.s.level / 5)
        let base = Int((80 + lvl * 85) * Double.random(in: 0.9...1.2))
        let hp = elite ? base * 4 : base
        return TNEnemy(name: m?.name ?? "Yêu Thú", emoji: m?.emoji ?? "🐺", hp: hp, hpMax: hp,
                       atk: Int(Double(game.s.atk) * (elite ? 0.85 : 0.55)),
                       def: Int(Double(game.s.def) * (elite ? 0.8 : 0.55)),
                       reward: Int((30 + lvl * 12) * (elite ? 4 : 1)),
                       exp: Int((25 + lvl * 15) * (elite ? 4 : 1)), isBoss: elite)
    }
    private func flash(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { withAnimation { if toast == m { toast = nil } } }
    }
    private func showCelebrate(_ t: String) {
        TNSound.level(); TNHaptic.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { celebrate = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { celebrate = nil } }
    }
}
