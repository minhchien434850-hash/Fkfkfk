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
