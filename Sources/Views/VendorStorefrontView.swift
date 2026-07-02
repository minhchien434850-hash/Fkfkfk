import SwiftUI

// §7 — Mặt tiền cửa hàng cá nhân (storefront) — hiển thị GIỐNG cửa hàng admin:
// banner/hero · badge · danh mục · thẻ sản phẩm "Mua ngay". Dùng cho:
//  • Chủ shop xem trước cửa hàng của mình (đúng cách khách nhìn thấy)
//  • Khách mở cửa hàng bất kỳ theo Store ID / link
struct VendorStorefrontView: View {
    let sid: Int
    var isOwner: Bool = false   // chủ shop → hiện nút quản lý (bút vẽ/bánh răng)
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var data: MyStoreResponse?
    @State private var loading = true
    @State private var selectedCat: Int? = nil
    @State private var buyProduct: MyStoreProduct?
    @State private var showManage = false

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var products: [MyStoreProduct] {
        let all = data?.products ?? []
        guard let c = selectedCat else { return all }
        return all.filter { $0.categoryId == c }
    }

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            } else if let s = data?.store {
                VStack(alignment: .leading, spacing: 16) {
                    hero(s)
                    badges
                    if let cats = data?.categories, !cats.isEmpty { categoryChips(cats) }
                    productsGrid
                }
                .padding()
            } else {
                Text("Không tải được cửa hàng.").foregroundStyle(.secondary).padding(.top, 60)
            }
        }
        .navigationTitle(data?.store?.name ?? "Cửa hàng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManage = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $buyProduct) { p in
            BuyProductView(product: p, storeId: sid).environmentObject(store)
        }
        .sheet(isPresented: $showManage, onDismiss: { Task { await load() } }) {
            MyStoreView().environmentObject(store)
        }
    }

    // Hero: banner (ẢNH · VIDEO · GIF — như storefront admin) + logo + tên + slogan
    @ViewBuilder private func hero(_ s: MyStore) -> some View {
        ZStack(alignment: .bottomLeading) {
            bannerMedia(s.bannerUrl).frame(height: 190).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 190)
            HStack(alignment: .bottom, spacing: 12) {
                if let l = s.logoUrl, !l.isEmpty, let u = URL(string: l) {
                    CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() }
                        placeholder: { Color.white.opacity(0.2) }
                        .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 3) {
                    LogoEffectText(text: s.name,
                                   effect: s.nameEffect ?? "gradient",
                                   font: .title3.bold(),
                                   solidColor: hexColor(s.nameColor))
                        .lineLimit(1)
                    if let sl = s.slogan, !sl.isEmpty {
                        let se = s.sloganEffect ?? "none"
                        LogoEffectText(text: sl,
                                       effect: (se == "none") ? "solid" : se,
                                       font: .caption.bold(),
                                       solidColor: hexColor(s.sloganColor) ?? .white.opacity(0.92))
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // Render media theo LINK: video → phát lặp; GIF/WEBP → động; còn lại → ảnh (như admin).
    @ViewBuilder private func bannerMedia(_ urlStr: String?) -> some View {
        if let s = urlStr, !s.isEmpty {
            if isVideoLink(s), let u = URL(string: s) {
                LoopingVideoBackground(url: u, fit: false)
            } else if isAnimatedImage(s), let u = URL(string: s) {
                GIFWebView(url: u, contentMode: "cover")
            } else if let u = URL(string: s) {
                CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() }
                    placeholder: { Theme.heroGradient }
            } else {
                Theme.heroGradient
            }
        } else {
            Theme.heroGradient
        }
    }

    // 4 badge uy tín (như storefront admin)
    private var badges: some View {
        let items: [(String, String, String, Color)] = [
            ("bolt.fill", "Kích hoạt tức thì", "Nhận key ngay sau thanh toán", .yellow),
            ("checkmark.shield.fill", "Bảo hành trọn đời", "Hỗ trợ đổi key miễn phí", .purple),
            ("headphones", "Hỗ trợ 24/7", "Luôn sẵn sàng giúp bạn", .blue),
            ("lock.fill", "An toàn & Bảo mật", "Mã hoá thông tin tuyệt đối", .green),
        ]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 10) {
                    Image(systemName: it.0).font(.title3).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(it.3).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.1).font(.caption.bold())
                        Text(it.2).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).kCard(12)
            }
        }
    }

    private func categoryChips(_ cats: [MyStoreCategory]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tất cả", active: selectedCat == nil) { selectedCat = nil }
                ForEach(cats) { c in
                    chip(c.name, active: selectedCat == c.id) { selectedCat = c.id }
                }
            }
        }
    }
    private func chip(_ t: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t).font(.caption.bold())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(active ? Theme.accent : Color(.secondarySystemBackground))
                .foregroundStyle(active ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private var productsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tất cả sản phẩm", systemImage: "bag.fill").font(.headline)
            if products.isEmpty {
                Text("Cửa hàng chưa có sản phẩm.").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(products) { p in productCard(p) }
                }
            }
        }
    }

    @ViewBuilder private func productCard(_ p: MyStoreProduct) -> some View {
        let inStock = (p.stock ?? 1) > 0
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let m = p.media?.first, !m.url.isEmpty {
                    bannerMedia(m.url).frame(height: 110).frame(maxWidth: .infinity).clipped()
                } else {
                    ZStack { Color(.tertiarySystemFill); Image(systemName: "photo").foregroundStyle(.secondary) }
                        .frame(height: 110).frame(maxWidth: .infinity)
                }
                Text(inStock ? "● ACTIVE" : "● Hết hàng")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial).foregroundStyle(inStock ? .green : .red)
                    .clipShape(Capsule()).padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(p.name).font(.subheadline.bold()).lineLimit(1)
            Text(priceText(p)).font(.caption.bold()).foregroundStyle(Theme.accent)
            Button { buyProduct = p } label: {
                Label("Mua ngay", systemImage: "cart.fill")
                    .font(.caption.bold()).frame(maxWidth: .infinity).frame(height: 34)
                    .background(inStock ? Theme.accent : Color.gray)
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).disabled(!inStock)
        }
        .padding(8).kCard(12)
    }

    private func priceText(_ p: MyStoreProduct) -> String {
        if let tiers = p.prices, tiers.count > 1 {
            let mn = tiers.map { $0.amount }.min() ?? p.price
            let mx = tiers.map { $0.amount }.max() ?? p.price
            return "\(kFormatVND(mn)) ~ \(kFormatVND(mx))"
        }
        return kFormatVND(p.price)
    }

    private func load() async {
        loading = true
        data = try? await store.api.getUserStore(sid)
        loading = false
    }
}

// Chuyển "#RRGGBB" (hoặc "RRGGBB") → Color. Rỗng/không hợp lệ → nil.
func hexColor(_ hex: String?) -> Color? {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    let r = Double((v >> 16) & 0xFF) / 255.0
    let g = Double((v >> 8) & 0xFF) / 255.0
    let b = Double(v & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}
