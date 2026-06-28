import SwiftUI
import AVKit
import Foundation

// ============================ Logo cửa hàng có hiệu ứng động ============================
// effect: rainbow | gold | neon | glow | none
// font:   rounded | serif | mono | default
// anim:   shimmer | wave | pulse | none
struct AnimatedStoreLogo: View {
    let text: String
    var effect: String = "rainbow"
    var fontStyle: String = "rounded"
    var anim: String = "shimmer"
    var size: CGFloat = 26

    private var font: Font {
        let design: Font.Design
        switch fontStyle {
        case "serif": design = .serif
        case "mono":  design = .monospaced
        case "rounded": design = .rounded
        default: design = .default
        }
        return .system(size: size, weight: .heavy, design: design)
    }
    private let rainbow: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 3)) / 3   // 0..1
            styled(phase)
                .scaleEffect(anim == "pulse" ? 1 + 0.06 * sin(phase * 2 * .pi) : 1)
                .rotationEffect(.degrees(anim == "wave" ? 2.5 * sin(phase * 2 * .pi) : 0))
                .animation(.linear(duration: 0.1), value: phase)
        }
        .frame(height: size + 8)
    }

    @ViewBuilder private func styled(_ phase: Double) -> some View {
        let base = Text(text).font(font)
        switch effect {
        case "rainbow":
            base.foregroundStyle(LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing))
                .hueRotation(.degrees(anim == "none" ? 0 : phase * 360))
        case "gradient":
            base.foregroundStyle(LinearGradient(colors: [Theme.accent, .cyan, .purple],
                                                startPoint: .leading, endPoint: .trailing))
        case "gold":
            base.foregroundStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.78, blue: 0.25), .yellow, Color(red: 0.82, green: 0.6, blue: 0.12)],
                startPoint: .top, endPoint: .bottom))
                .shadow(color: .yellow.opacity(0.5), radius: 4)
        case "neon":
            base.foregroundStyle(.cyan)
                .shadow(color: .cyan, radius: 8).shadow(color: .blue, radius: 14)
        case "glow":
            base.foregroundStyle(.white)
                .shadow(color: .white.opacity(0.85), radius: anim == "none" ? 4 : 4 + 6 * abs(sin(phase * .pi)))
        case "accent":
            base.foregroundStyle(Theme.accent)
        default:
            base.foregroundStyle(.primary)
        }
    }
}

// ============================ Nền cửa hàng full màn hình (ảnh/GIF/video) ============================
struct StoreBackground: View {
    let type: String   // none | image | video
    let url: String

    var body: some View {
        Group {
            if type == "video", let u = URL(string: url) {
                LoopingVideoBackground(url: u)
            } else if type == "image", let u = URL(string: url) {
                if url.lowercased().contains(".gif") {
                    GIFWebView(url: u, contentMode: "cover")
                } else {
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() }
                    placeholder: { Color.clear }
                }
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)   // để thao tác nằm trên nền vẫn bấm được
    }
}

// Video nền lặp vô hạn, tắt tiếng — tự động phát lại khi app lên foreground
final class LoopingPlayerUIView: UIView {
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var activeObserver: NSObjectProtocol?
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL, fit: Bool = false) {
        super.init(frame: .zero)
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer(playerItem: item)
        p.isMuted = true
        looper = AVPlayerLooper(player: p, templateItem: item)
        playerLayer.player = p
        // fit = hiện ĐỦ video trong khung (không cắt); mặc định fill = lấp đầy (có thể cắt)
        playerLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        p.play()
        queuePlayer = p
        // Tự phát lại khi app quay lại foreground (tránh video dừng khi mở lại)
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak p] _ in p?.play() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { queuePlayer?.play() }
    }

    deinit {
        if let obs = activeObserver { NotificationCenter.default.removeObserver(obs) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

struct LoopingVideoBackground: UIViewRepresentable {
    let url: URL
    var fit: Bool = false   // true = hiện đủ video trong khung (không cắt)
    func makeUIView(context: Context) -> LoopingPlayerUIView { LoopingPlayerUIView(url: url, fit: fit) }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

// ============================ Hiệu ứng chạm kiểu iOS 26 ============================
// Nút thu nhỏ mềm + rung nhẹ khi chạm (Liquid Glass feel)
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
    }
}

extension View {
    /// Áp hiệu ứng chạm iOS 26 cho 1 view bất kỳ (dùng cho thẻ chạm được)
    func iosTapEffect() -> some View { buttonStyle(PressableButtonStyle()) }
}

// ============================ Chữ có hiệu ứng linh hoạt (dùng cho slogan / hero text) ============================
// Không giới hạn font/weight — truyền font tuỳ ý từ bên ngoài.
struct AnimatedStoreText: View {
    let text: String
    var effect: String = "none"
    var font: Font = .body
    var anim: String = "none"

    private let rainbow: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 3)) / 3
            styled(phase)
                .scaleEffect(anim == "pulse" ? 1 + 0.06 * sin(phase * 2 * .pi) : 1)
                .rotationEffect(.degrees(anim == "wave" ? 2.5 * sin(phase * 2 * .pi) : 0))
        }
    }

    @ViewBuilder private func styled(_ phase: Double) -> some View {
        let base = Text(text).font(font)
        switch effect {
        case "rainbow":
            base.foregroundStyle(LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing))
                .hueRotation(.degrees(anim == "none" ? 0 : phase * 360))
        case "gradient":
            base.foregroundStyle(LinearGradient(colors: [Theme.accent, .cyan, .purple],
                                                startPoint: .leading, endPoint: .trailing))
        case "gold":
            base.foregroundStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.78, blue: 0.25), .yellow,
                         Color(red: 0.82, green: 0.6, blue: 0.12)],
                startPoint: .top, endPoint: .bottom))
        case "neon":
            base.foregroundStyle(.cyan).shadow(color: .cyan, radius: 8).shadow(color: .blue, radius: 14)
        case "glow":
            base.foregroundStyle(.white)
                .shadow(color: .white.opacity(0.85), radius: anim == "none" ? 4 : 4 + 6 * abs(sin(phase * .pi)))
        case "accent":
            base.foregroundStyle(Theme.accent)
        default:
            base.foregroundStyle(.secondary)
        }
    }
}

// Danh sách tuỳ chọn hiệu ứng / font (dùng cho cả cửa hàng & cài đặt app)
let kLogoEffects: [(String, String)] = [
    ("rainbow", "7 màu chạy"), ("gradient", "Gradient màu app"),
    ("gold", "Vàng kim"), ("neon", "Neon"),
    ("glow", "Phát sáng"), ("accent", "Màu accent"), ("none", "Không")
]
let kLogoFonts: [(String, String)] = [
    ("rounded", "Bo tròn"), ("default", "Mặc định"), ("serif", "Có chân"), ("mono", "Đơn cách")
]
let kLogoAnims: [(String, String)] = [
    ("shimmer", "Lung linh"), ("wave", "Lượn sóng"), ("pulse", "Nhịp đập"), ("none", "Tĩnh")
]

// Bộ font đa dạng cho dòng giới thiệu (slogan) cửa hàng
let kSloganFonts: [(String, String)] = [
    ("rounded", "Bo tròn"), ("default", "Mặc định"), ("serif", "Có chân"),
    ("mono", "Đơn cách"), ("serif-italic", "Có chân nghiêng"), ("rounded-bold", "Bo tròn đậm"),
    ("italic", "Nghiêng"), ("thin", "Mảnh"), ("heavy", "Đậm khối"),
    ("mono-bold", "Đơn cách đậm")
]

/// Tạo Font đa dạng từ tên kiểu (dùng cho slogan cửa hàng).
func keniosFont(_ style: String, size: CGFloat) -> Font {
    let design: Font.Design
    switch style {
    case "serif", "serif-italic":   design = .serif
    case "mono", "mono-bold":        design = .monospaced
    case "rounded", "rounded-bold":  design = .rounded
    default:                          design = .default
    }
    let weight: Font.Weight
    switch style {
    case "thin":                                weight = .light
    case "heavy", "rounded-bold", "mono-bold":  weight = .heavy
    default:                                     weight = .semibold
    }
    var f = Font.system(size: size, weight: weight, design: design)
    if style == "italic" || style == "serif-italic" { f = f.italic() }
    return f
}
