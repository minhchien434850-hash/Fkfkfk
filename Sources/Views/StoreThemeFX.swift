import SwiftUI
import AVKit
import Foundation

// ============================ Logo cửa hàng / app có hiệu ứng động ============================
// effect: rainbow|gradient|gold|silver|neon|glow|fire|ocean|sunset|candy|galaxy|mint|accent|none
// font:   rounded|serif|mono|default
// anim:   shimmer|wave|pulse|bounce|rotate|blink|rgb|none
// LƯU Ý: mọi hiệu ứng (anim) đều CHẠY trên MỌI màu (effect) — không còn cảnh chọn xong mà đứng im.
struct AnimatedStoreLogo: View {
    let text: String
    var effect: String = "rainbow"
    var fontStyle: String = "rounded"
    var anim: String = "shimmer"
    var size: CGFloat = 26

    private var font: Font { keniosLogoFont(fontStyle, size: size) }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 2)) / 2   // 0..1 mỗi 2 giây
            LogoEffectText(text: text, effect: effect, font: font)
                .modifier(LogoAnimModifier(anim: anim, phase: p))
                .overlay { if anim == "shimmer" { ShimmerSweep(text: text, font: font, phase: p) } }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)   // hiện ĐỦ chữ (vd "KENIOS"), không bị cắt thành "K…"
        .frame(height: size + 10)
    }
}

// Bộ biến đổi chuyển động (áp cho mọi màu): nảy, lắc, nhịp đập, nhấp nháy, đổi màu…
struct LogoAnimModifier: ViewModifier {
    let anim: String
    let phase: Double
    func body(content: Content) -> some View {
        let s = sin(phase * 2 * .pi)
        return content
            .scaleEffect(anim == "pulse" ? 1 + 0.08 * s : 1)
            .offset(y: (anim == "wave" || anim == "bounce") ? CGFloat(5 * s) : 0)
            .rotationEffect(.degrees(anim == "rotate" ? 3.5 * s : 0))
            .opacity(anim == "blink" ? 0.45 + 0.55 * abs(sin(phase * .pi)) : 1)
            .hueRotation(.degrees(anim == "rgb" ? phase * 360 : 0))
    }
}

// Văn bản đổ màu theo hiệu ứng (dùng chung cho logo + slogan + hero).
struct LogoEffectText: View {
    let text: String
    let effect: String
    let font: Font
    var solidColor: Color? = nil   // dùng khi effect == "solid" (màu admin tự chọn)
    private let rainbow: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]

    var body: some View {
        let base = Text(text).font(font)
        switch effect {
        case "solid":
            base.foregroundStyle(solidColor ?? .primary)
        case "rainbow":
            base.foregroundStyle(LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing))
        case "gradient":
            base.foregroundStyle(LinearGradient(colors: [Theme.accent, .cyan, .purple], startPoint: .leading, endPoint: .trailing))
        case "gold":
            base.foregroundStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.25), .yellow, Color(red: 0.82, green: 0.6, blue: 0.12)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .yellow.opacity(0.5), radius: 3)
        case "silver":
            base.foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.55), .white], startPoint: .top, endPoint: .bottom))
        case "neon":
            base.foregroundStyle(.cyan).shadow(color: .cyan, radius: 8).shadow(color: .blue, radius: 14)
        case "glow":
            base.foregroundStyle(.white).shadow(color: .white.opacity(0.85), radius: 6)
        case "fire":
            base.foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .bottom, endPoint: .top))
                .shadow(color: .orange.opacity(0.6), radius: 5)
        case "ocean":
            base.foregroundStyle(LinearGradient(colors: [.cyan, .blue, .teal], startPoint: .leading, endPoint: .trailing))
        case "sunset":
            base.foregroundStyle(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
        case "candy":
            base.foregroundStyle(LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .leading, endPoint: .trailing))
        case "galaxy":
            base.foregroundStyle(LinearGradient(colors: [.purple, .indigo, .blue, .purple], startPoint: .leading, endPoint: .trailing))
                .shadow(color: .purple.opacity(0.5), radius: 4)
        case "mint":
            base.foregroundStyle(LinearGradient(colors: [.green, .mint, .teal], startPoint: .leading, endPoint: .trailing))
        case "accent":
            base.foregroundStyle(Theme.accent)
        case "secondary":
            base.foregroundStyle(.secondary)
        default:
            base.foregroundStyle(.primary)
        }
    }
}

// Vệt sáng "lung linh" quét qua chữ — nhìn rõ trên MỌI màu.
struct ShimmerSweep: View {
    let text: String
    let font: Font
    let phase: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.95), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: max(40, w * 0.35))
                .offset(x: -w * 0.7 + (w * 1.4) * phase)
                .blendMode(.plusLighter)
        }
        .mask(Text(text).font(font))
        .allowsHitTesting(false)
    }
}

// Font cho logo (đậm khối) theo kiểu chữ chọn.
func keniosLogoFont(_ style: String, size: CGFloat) -> Font {
    let design: Font.Design
    switch style {
    case "serif": design = .serif
    case "mono":  design = .monospaced
    case "rounded": design = .rounded
    default: design = .default
    }
    return .system(size: size, weight: .heavy, design: design)
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
                    // Dùng ảnh có CACHE → khi quay lại tab/app không bị trắng/đen rồi mới hiện.
                    CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() }
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

// BỂ CHỨA player video (giữ sống theo URL) — chống "chớp đen" khi quay lại tab/app.
// Player vẫn chạy ngầm khi rời màn → quay lại GẮN LẠI là có khung hình ngay, không phải tải lại từ đen.
extension Notification.Name {
    // Bắn khi 1 video nền vừa tải xong → view đang hiển thị đổi sang bản LOCAL (mượt).
    static let loopingPlayerUpgraded = Notification.Name("kenios.loopingPlayerUpgraded")
}

final class LoopingPlayerPool {
    static let shared = LoopingPlayerPool()
    private var cache: [String: (player: AVQueuePlayer, looper: AVPlayerLooper)] = [:]
    private var order: [String] = []
    private let capacity = 10   // giữ tối đa 10 video gần nhất để khỏi tốn bộ nhớ

    func player(for url: URL) -> AVQueuePlayer {
        let key = url.absoluteString
        if let e = cache[key] { touch(key); return e.player }
        let local = Self.cachedFileURL(for: url)
        let p = makePlayer(playURL: local ?? url, isLocal: local != nil)
        cache[key] = p
        order.append(key)
        while order.count > capacity {
            let k = order.removeFirst()
            if k != key { cache[k]?.player.pause(); cache[k] = nil }
        }
        // Chưa có bản local → tải về rồi TỰ ĐỔI player sang local ngay (hết đứng khi lặp).
        if local == nil { downloadAndUpgrade(url, key: key) }
        return p.player
    }

    private func makePlayer(playURL: URL, isLocal: Bool) -> (player: AVQueuePlayer, looper: AVPlayerLooper) {
        // Timing chính xác → điểm nối vòng lặp khít, không lệch/giật.
        let asset = AVURLAsset(url: playURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = isLocal ? 0 : 6   // remote: nạp sẵn nhiều để đỡ stall
        let p = AVQueuePlayer()               // rỗng → AVPlayerLooper tự nạp bản sao (lặp liền mạch)
        p.isMuted = true
        p.actionAtItemEnd = .none
        p.automaticallyWaitsToMinimizeStalling = !isLocal  // local phát ngay; remote chờ đủ buffer
        let looper = AVPlayerLooper(player: p, templateItem: item)
        return (p, looper)
    }

    private func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
    }

    // ---- Cache video nền xuống đĩa (Caches) để lặp không phụ thuộc mạng ----
    private static let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    private var downloading = Set<String>()

    private static func stableName(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
    private static func cacheFile(for url: URL) -> URL {
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return cachesDir.appendingPathComponent("kenios_vbg_\(stableName(url.absoluteString)).\(ext)")
    }
    static func cachedFileURL(for url: URL) -> URL? {
        guard url.scheme?.hasPrefix("http") == true else { return url }   // vốn đã là file local
        let f = cacheFile(for: url)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    private func downloadAndUpgrade(_ url: URL, key: String) {
        guard url.scheme?.hasPrefix("http") == true, !downloading.contains(key) else { return }
        downloading.insert(key)
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, resp, _ in
            guard let self else { return }
            guard let tmp,
                  let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
                DispatchQueue.main.async { self.downloading.remove(key) }; return
            }
            let dest = Self.cacheFile(for: url)
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.moveItem(at: tmp, to: dest) }
            catch { DispatchQueue.main.async { self.downloading.remove(key) }; return }
            DispatchQueue.main.async {
                self.downloading.remove(key)
                // Dựng player mới từ FILE LOCAL, thay vào bể chứa, rồi báo view đổi sang.
                let old = self.cache[key]?.player
                self.cache[key] = self.makePlayer(playURL: dest, isLocal: true)
                self.cache[key]?.player.play()
                old?.pause()
                NotificationCenter.default.post(name: .loopingPlayerUpgraded, object: key)
            }
        }.resume()
    }
}

// Video nền lặp vô hạn, tắt tiếng — dùng player từ bể chứa (không tải lại → không chớp đen).
final class LoopingPlayerUIView: UIView {
    private var player: AVQueuePlayer?
    private let urlKey: String
    private var activeObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var upgradeObserver: NSObjectProtocol?
    private var watchdog: Timer?
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL, fit: Bool = false) {
        self.urlKey = url.absoluteString
        super.init(frame: .zero)
        backgroundColor = .clear
        let p = LoopingPlayerPool.shared.player(for: url)
        player = p
        playerLayer.player = p
        // fit = hiện ĐỦ video trong khung (không cắt); mặc định fill = lấp đầy (có thể cắt)
        playerLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        p.play()
        // Tự phát lại khi app quay lại foreground (tránh video dừng khi mở lại)
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.playerLayer.player !== self.player { self.playerLayer.player = self.player }
                self.player?.play()
            }
        // Tải xong bản LOCAL → đổi ngay sang player local (mượt, hết đứng khi lặp).
        upgradeObserver = NotificationCenter.default.addObserver(
            forName: .loopingPlayerUpgraded, object: nil, queue: .main) { [weak self] note in
                guard let self, (note.object as? String) == self.urlKey else { return }
                let np = LoopingPlayerPool.shared.player(for: URL(string: self.urlKey) ?? url)
                self.player = np
                self.playerLayer.player = np
                np.play()
            }
        // Bị NGHẼN buffer (stall) → phát lại NGAY khi có thể, không để đứng chờ lâu.
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil, queue: .main) { [weak self] _ in self?.player?.play() }
        // Watchdog: nếu vì lý do nào đó player dừng khi đang hiển thị → tự chạy lại.
        let wd = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self, self.window != nil, let p = self.player else { return }
            if p.timeControlStatus != .playing { p.play() }
        }
        RunLoop.main.add(wd, forMode: .common)
        watchdog = wd
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            // Gắn lại player vào layer này (phòng khi nó vừa ở layer khác) rồi phát tiếp ngay.
            if playerLayer.player !== player { playerLayer.player = player }
            player?.play()
        }
    }

    deinit {
        // KHÔNG huỷ player — bể chứa giữ nó sống để lần sau quay lại không bị chớp đen.
        if let obs = activeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = stallObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = upgradeObserver { NotificationCenter.default.removeObserver(obs) }
        watchdog?.invalidate()
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
    var solidColor: Color? = nil   // màu admin tự chọn (khi effect == "solid")

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 2)) / 2
            LogoEffectText(text: text, effect: effect == "none" ? "secondary" : effect, font: font, solidColor: solidColor)
                .modifier(LogoAnimModifier(anim: anim, phase: p))
                .overlay { if anim == "shimmer" { ShimmerSweep(text: text, font: font, phase: p) } }
        }
    }
}

// Chuyển chuỗi hex (#RRGGBB / RRGGBB / #RRGGBBAA) → Color. Rỗng/không hợp lệ = nil.
extension Color {
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // Color → "#RRGGBB" để lưu lên server.
    var hexStringRGB: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        #else
        return "#000000"
        #endif
    }
}

// Danh sách tuỳ chọn hiệu ứng / font (dùng cho cả cửa hàng & cài đặt app)
let kLogoEffects: [(String, String)] = [
    ("solid", "Màu tự chọn 🎨"),
    ("rainbow", "7 màu chạy"), ("gradient", "Gradient màu app"), ("gold", "Vàng kim"),
    ("silver", "Bạc"), ("neon", "Neon"), ("glow", "Phát sáng"),
    ("fire", "Lửa"), ("ocean", "Đại dương"), ("sunset", "Hoàng hôn"),
    ("candy", "Kẹo ngọt"), ("galaxy", "Thiên hà"), ("mint", "Bạc hà"),
    ("accent", "Màu accent"), ("none", "Không")
]
let kLogoFonts: [(String, String)] = [
    ("rounded", "Bo tròn"), ("default", "Mặc định"), ("serif", "Có chân"), ("mono", "Đơn cách")
]
let kLogoAnims: [(String, String)] = [
    ("shimmer", "Lung linh"), ("wave", "Lượn sóng"), ("pulse", "Nhịp đập"),
    ("bounce", "Nảy"), ("rotate", "Lắc lư"), ("blink", "Nhấp nháy"),
    ("rgb", "Đổi màu"), ("none", "Tĩnh")
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
