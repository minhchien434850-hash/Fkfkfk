import SwiftUI
import AVKit
import WebKit

// ============================ GIF động (dùng WKWebView, không cần thư viện ngoài) ============================
struct GIFWebView: UIViewRepresentable {
    let url: URL
    var contentMode: String = "cover"   // "cover" | "contain"

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.scrollView.isScrollEnabled = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        let html = """
        <html>
        <head><meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>body{margin:0;padding:0;background:transparent;}
        img{width:100%;height:100vh;object-fit:\(contentMode);display:block;}</style></head>
        <body><img src='\(url.absoluteString)'></body></html>
        """
        w.loadHTMLString(html, baseURL: nil)
    }
}

// ============================ Bộ nhớ đệm ảnh (chống nhấp nháy khi quay lại trang) ============================
/// Giữ ảnh đã tải trong RAM để khi rời trang rồi vào lại KHÔNG phải tải lại (đứng yên 100%).
enum StoreImageCache {
    nonisolated(unsafe) static let memory = NSCache<NSURL, UIImage>()
}

/// Ảnh tải từ link có CACHE — thay cho AsyncImage để không nhấp nháy/nạp lại.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let img = uiImage ?? StoreImageCache.memory.object(forKey: url as NSURL) {
                content(Image(uiImage: img))
            } else {
                placeholder().task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        if let cached = StoreImageCache.memory.object(forKey: url as NSURL) {
            uiImage = cached; return
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad   // tận dụng URLCache trên đĩa giữa các lần mở app
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        StoreImageCache.memory.setObject(img, forKey: url as NSURL)
        uiImage = img
    }
}

/// True nếu link là ảnh động (GIF/WEBP) → render bằng WKWebView để chạy động.
func isAnimatedImage(_ s: String) -> Bool {
    let l = s.lowercased()
    return l.contains(".gif") || l.contains(".webp")
}

/// True nếu link là video (MP4/MOV/M3U8/WEBM...) → render bằng trình phát video lặp.
func isVideoLink(_ s: String) -> Bool {
    let l = s.lowercased()
    return l.contains(".mp4") || l.contains(".mov") || l.contains(".m3u8")
        || l.contains(".webm") || l.contains(".m4v")
}

// ============================ Tiện ích chung ============================
func kFormatVND(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return (f.string(from: NSNumber(value: amount)) ?? "\(amount)") + "đ"
}

// Số nguyên có dấu chấm nhóm nghìn (không có "đ") — dùng cho ô thống kê
func kGroupNumber(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

// Carousel ảnh/video (link) — tối đa 5, hỗ trợ GIF động + video lặp vô hạn
struct StoreMediaCarousel: View {
    let media: [StoreMedia]
    var height: CGFloat = 200
    var videoFit: Bool = false   // true = video hiện ĐỦ khung, không bị cắt (dùng cho hero)

    var body: some View {
        if media.isEmpty {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .frame(height: height)
                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
        } else {
            TabView {
                ForEach(Array(media.prefix(5).enumerated()), id: \.offset) { _, m in
                    if m.type == "video", let url = URL(string: m.url) {
                        LoopingVideoBackground(url: url, fit: videoFit)
                            .frame(height: height)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else if let url = URL(string: m.url) {
                        storeImage(url: url, height: height)
                    }
                }
            }
            .frame(height: height)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }
}

// Hiển thị ảnh từ link — tự động dùng GIFWebView khi là .gif
@ViewBuilder
private func storeImage(url: URL, height: CGFloat) -> some View {
    if isAnimatedImage(url.absoluteString) {
        GIFWebView(url: url)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    } else {
        CachedAsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ProgressView().frame(maxWidth: .infinity)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Ảnh/video thu nhỏ — hỗ trợ video lặp vô hạn tự động
struct StoreThumb: View {
    let media: [StoreMedia]
    var height: CGFloat = 120

    private var first: StoreMedia? { media.first }

    var body: some View {
        ZStack {
            if let m = first {
                if m.type == "video", let url = URL(string: m.url) {
                    LoopingVideoBackground(url: url)
                } else if let url = URL(string: m.url) {
                    if isAnimatedImage(m.url) {
                        GIFWebView(url: url)
                    } else {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.tertiarySystemBackground)
                        }
                    }
                }
            } else {
                Color(.tertiarySystemBackground)
                Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
            }
            if media.count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(media.count) ảnh")
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.ultraThinMaterial).clipShape(Capsule())
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// Dải tự cuộn (giao dịch / nạp tiền gần đây) — đổi 6 dòng mỗi 5 giây.
/// TÁCH RIÊNG khỏi StoreView: timer + chỉ số cuộn nằm trong chính view này nên
/// mỗi 5 giây CHỈ dải này vẽ lại, KHÔNG kéo cả cửa hàng vẽ lại theo (hết nháy).
struct AutoScrollTicker<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var visible: Int = 6
    @ViewBuilder let row: (Item) -> Row

    @State private var index = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var window: [Item] {
        guard items.count > visible else { return items }
        let start = ((index % items.count) + items.count) % items.count
        return (0..<visible).map { items[(start + $0) % items.count] }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(window) { item in
                VStack(spacing: 0) {
                    row(item).padding(.vertical, 8)
                    Divider()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .padding(.horizontal, 12)
        .clipped()
        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.55), value: index)
        .onReceive(timer) { _ in if items.count > visible { index += 1 } }
    }
}

