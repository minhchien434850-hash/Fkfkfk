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

// ============================ Tiện ích chung ============================
func kFormatVND(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return (f.string(from: NSNumber(value: amount)) ?? "\(amount)") + "đ"
}

// Carousel ảnh/video (link) — tối đa 5, hỗ trợ GIF động
struct StoreMediaCarousel: View {
    let media: [StoreMedia]
    var height: CGFloat = 200

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
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: height)
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
    if url.absoluteString.lowercased().contains(".gif") {
        GIFWebView(url: url)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    } else {
        AsyncImage(url: url) { img in
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

// Ảnh thu nhỏ TĨNH (không vuốt) — dùng cho thẻ trong lưới để không nuốt thao tác chạm
struct StoreThumb: View {
    let media: [StoreMedia]
    var height: CGFloat = 120

    private var first: StoreMedia? { media.first }

    var body: some View {
        ZStack {
            if let m = first, m.type != "video", let url = URL(string: m.url) {
                if m.url.lowercased().contains(".gif") {
                    GIFWebView(url: url)
                } else {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemBackground)
                    }
                }
            } else if first?.type == "video" {
                Color.black.opacity(0.85)
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
            } else {
                Color(.tertiarySystemBackground)
                Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
            }
            if (media.count) > 1 {
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

// ============================ App bán hàng (khách) ============================
struct StoreView: View {
    @EnvironmentObject var store: AppStore

    @State private var config: StoreAppConfig?
    @State private var categories: [StoreCategory] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdmin = false
    @State private var showMyOrders = false
    @State private var showWallet = false
    @State private var showSearch = false
    @State private var downloads: [StoreDownloadItem] = []
    @State private var contacts: StoreContacts?
    @State private var search = ""
    @State private var allProducts: [StoreProduct] = []
    @State private var loadingProducts = false
    @AppStorage("storeWishlist") private var wishlistRaw: String = ""
    @AppStorage("storeRecentViews") private var recentViewsRaw: String = ""
    // Cache cấu hình cửa hàng — giữ tên/logo/banner khi mất kết nối, không bị reset về mặc định
    @AppStorage("storeCfgName") private var cfgName: String = ""
    @AppStorage("storeCfgLogo") private var cfgLogo: String = ""
    @AppStorage("storeCfgBannerType") private var cfgBannerType: String = "image"
    @AppStorage("storeCfgBannerUrl") private var cfgBannerUrl: String = ""
    @State private var storeHasData: Bool = false
    @State private var productSort: String = "default"  // default | priceAsc | priceDesc | name
    @State private var productFilter: String = "all"    // all | inStock
    @State private var showCart = false
    @AppStorage("storeCartRaw") private var cartRaw: String = "[]"

    private var displayName: String {
        if let n = config?.logoName, !n.isEmpty { return n }
        return cfgName.isEmpty ? "Cửa hàng" : cfgName
    }
    // Cấu hình hiệu lực: ưu tiên server, fallback cache (để banner/logo không biến mất khi offline)
    private var effectiveConfig: StoreAppConfig? {
        if let c = config { return c }
        if cfgName.isEmpty && cfgLogo.isEmpty && cfgBannerUrl.isEmpty { return nil }
        return StoreAppConfig(logoName: cfgName, logoUrl: cfgLogo,
                              bannerType: cfgBannerType, bannerUrl: cfgBannerUrl,
                              topupBonusPercent: nil)
    }

    private var cartItems: [CartItem] {
        (try? JSONDecoder().decode([CartItem].self, from: Data(cartRaw.utf8))) ?? []
    }

    private var displayProducts: [StoreProduct] {
        var prods = allProducts
        if productFilter == "inStock" { prods = prods.filter { $0.availableKeys > 0 } }
        switch productSort {
        case "priceAsc":  prods.sort { ($0.prices.first?.amount ?? 0) < ($1.prices.first?.amount ?? 0) }
        case "priceDesc": prods.sort { ($0.prices.first?.amount ?? 0) > ($1.prices.first?.amount ?? 0) }
        case "name":      prods.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        default: break
        }
        return prods
    }

    private var wishlistIds: Set<Int> {
        Set(wishlistRaw.split(separator: ",").compactMap { Int($0) })
    }
    private var recentViewIds: [Int] {
        recentViewsRaw.split(separator: ",").compactMap { Int($0) }
    }
    private var wishlistProducts: [StoreProduct] {
        let ids = wishlistIds
        return allProducts.filter { ids.contains($0.id) }
    }
    private var recentProducts: [StoreProduct] {
        let ids = recentViewIds
        let map = Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }
    private func toggleWishlist(_ id: Int) {
        var ids = wishlistIds
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        wishlistRaw = ids.map(String.init).joined(separator: ",")
    }

    private var filteredCategories: [StoreCategory] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // Kích cỡ thẻ — theo hệ số kéo của admin (Kích cỡ thẻ hiển thị)
    private var cardScale: CGFloat {
        if let s = config?.cardScale ?? effectiveConfig?.cardScale, let v = Double(s) {
            return CGFloat(max(0.6, min(v, 1.6)))
        }
        switch config?.cardSize ?? effectiveConfig?.cardSize {
        case "small": return 0.8
        case "large": return 1.25
        default:      return 1.0
        }
    }
    private var productCardWidth: CGFloat { 124 * cardScale }
    private var productThumbHeight: CGFloat { 84 * cardScale }
    private var categoryThumbHeight: CGFloat { 120 * cardScale }
    private var categoryGrid: [GridItem] {
        let n = cardScale < 0.85 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: n)
    }

    // Thứ tự bố cục các mục — theo cấu hình admin (Sắp xếp bố cục trang)
    private var orderedSections: [String] {
        let all = ["categories", "products", "downloads", "contacts", "wishlist", "recent"]
        guard let raw = (config?.sectionOrder ?? effectiveConfig?.sectionOrder), !raw.isEmpty else { return all }
        let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        var merged = parts.filter { all.contains($0) }
        for k in all where !merged.contains(k) { merged.append(k) }
        return merged
    }

    @ViewBuilder
    private func sectionView(_ key: String) -> some View {
        switch key {
        case "categories":
            if !categories.isEmpty { searchField }
            if loading && categories.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
            } else if categories.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: categoryGrid, spacing: 12) {
                    ForEach(filteredCategories) { cat in
                        NavigationLink {
                            StoreFolderListView(category: cat)
                        } label: { categoryCard(cat) }
                        .buttonStyle(.plain)
                    }
                }
            }
        case "products":
            if !allProducts.isEmpty { allProductsSection }
        case "downloads":
            if !downloads.isEmpty { downloadsSection }
        case "contacts":
            if let c = contacts, (!c.contact.isEmpty || !c.groups.isEmpty) {
                StoreContactsBlock(contacts: c)
            }
        case "wishlist":
            if !wishlistProducts.isEmpty { wishlistSection }
        case "recent":
            if !recentProducts.isEmpty { recentlyViewedSection }
        default:
            EmptyView()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storeHeader

                    walletBar

                    // Các mục hiển thị theo thứ tự admin sắp xếp (Sắp xếp bố cục trang)
                    ForEach(orderedSections, id: \.self) { key in
                        sectionView(key)
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .background {
                if let c = effectiveConfig, let bt = c.bgType, bt != "none",
                   let bu = c.bgUrl, !bu.isEmpty {
                    StoreBackground(type: bt, url: bu)
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Button { showMyOrders = true } label: {
                            Image(systemName: "bag.badge.questionmark")
                        }
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        Button { showCart = true } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "cart")
                                if !cartItems.isEmpty {
                                    Text("\(cartItems.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                        .background(Color.red)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        appearanceMenu
                        if store.isAdmin {
                            Button { showAdmin = true } label: { Image(systemName: "gearshape.fill") }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdmin) {
                StoreAdminView()
                    .onDisappear { Task { await reload() } }
            }
            .sheet(isPresented: $showMyOrders) { StoreMyOrdersView() }
            .sheet(isPresented: $showWallet) { StoreWalletView() }
            .sheet(isPresented: $showSearch) { StoreGlobalSearchView(categories: categories) }
            .sheet(isPresented: $showCart) { StoreCartView() }
            .task {
                await reload()
                // Polling mỗi 30 giây để cập nhật sản phẩm mới real-time
                let prevCatCount = categories.count
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    let oldCount = categories.count
                    await reload()
                    // Gửi thông báo nếu có danh mục/sản phẩm mới
                    if categories.count > oldCount && oldCount > 0 {
                        store.postProductNotification(
                            body: "KENIOS vừa cập nhật \(categories.count - oldCount) danh mục sản phẩm mới!")
                    }
                    _ = prevCatCount  // suppress warning
                }
            }
            .refreshable { await reload() }
        }
    }

    private var appearanceMenu: some View { AppearanceMenu() }

    // Thanh ví: bấm để nạp tiền / xem số dư
    private var walletBar: some View {
        Button { showWallet = true } label: {
            HStack {
                Image(systemName: "wallet.pass.fill").foregroundStyle(Theme.gold)
                Text(store.t("Ví cửa hàng", "Store wallet")).font(.subheadline.bold())
                if let pct = config?.topupBonusPercent, pct > 0 {
                    Text("KM +\(pct)%").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pink.opacity(0.2)).foregroundStyle(.pink)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(store.t("Nạp tiền", "Top up")).font(.caption).foregroundStyle(Theme.accent)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // Mục "Tải về" hiện ngay khi vào cửa hàng (bản tải miễn phí)
    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("Tải về", "Downloads"), systemImage: "arrow.down.circle.fill").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(downloads) { d in
                        downloadCard(d)
                    }
                }
            }
        }
    }

    private func downloadCard(_ d: StoreDownloadItem) -> some View {
        let url = !d.downloadUrl.isEmpty ? URL(string: d.downloadUrl) : store.api.storeDownloadURL(productId: d.id)
        return VStack(alignment: .leading, spacing: 0) {
            StoreThumb(media: d.media, height: 90)
            VStack(alignment: .leading, spacing: 4) {
                Text(d.name).font(.caption.bold()).lineLimit(2)
                if let url {
                    Link(destination: url) {
                        Label(store.t("Tải", "Get"), systemImage: "arrow.down.circle")
                            .font(.caption2.bold())
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.15)).foregroundStyle(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 150)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Toàn bộ sản phẩm — hiện ngay khi vào cửa hàng
    private var allProductsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(store.t("Tất cả sản phẩm", "All products"), systemImage: "bag.fill")
                    .font(.headline)
                Spacer()
                Menu {
                    Section(store.t("Sắp xếp", "Sort")) {
                        Button { productSort = "default" } label: {
                            Label(store.t("Mặc định", "Default"), systemImage: productSort == "default" ? "checkmark" : "list.number")
                        }
                        Button { productSort = "priceAsc" } label: {
                            Label(store.t("Giá tăng dần", "Price: low to high"), systemImage: productSort == "priceAsc" ? "checkmark" : "arrow.up.circle")
                        }
                        Button { productSort = "priceDesc" } label: {
                            Label(store.t("Giá giảm dần", "Price: high to low"), systemImage: productSort == "priceDesc" ? "checkmark" : "arrow.down.circle")
                        }
                        Button { productSort = "name" } label: {
                            Label(store.t("Tên A-Z", "Name A-Z"), systemImage: productSort == "name" ? "checkmark" : "textformat.abc")
                        }
                    }
                    Section(store.t("Lọc", "Filter")) {
                        Button {
                            productFilter = productFilter == "inStock" ? "all" : "inStock"
                        } label: {
                            Label(store.t("Chỉ còn hàng", "In stock only"), systemImage: productFilter == "inStock" ? "checkmark.circle.fill" : "shippingbox")
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(productSort != "default" || productFilter != "all" ? Theme.accent : .secondary)
                }
                Text("\(displayProducts.count) sp")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayProducts) { product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func allProductCard(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                StoreThumb(media: p.media, height: productThumbHeight)
                Button { toggleWishlist(p.id) } label: {
                    Image(systemName: wishlistIds.contains(p.id) ? "heart.fill" : "heart")
                        .font(.caption2.bold())
                        .foregroundStyle(wishlistIds.contains(p.id) ? .red : .white)
                        .padding(5)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(p.name)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !p.prices.isEmpty {
                    Text(kFormatVND(p.prices[0].amount))
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                }
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 10))
                    Text(store.t("Mua", "Buy"))
                        .font(.caption2.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(7)
        }
        .frame(width: productCardWidth)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
    }

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.t("Yêu thích", "Wishlist"), systemImage: "heart.fill")
                    .font(.headline).foregroundStyle(.red)
                Spacer()
                Text("\(wishlistProducts.count) " + store.t("sản phẩm", "products"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wishlistProducts) { product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var recentlyViewedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.t("Đã xem gần đây", "Recently viewed"), systemImage: "clock.arrow.circlepath")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentProducts) { product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(store.t("Tìm danh mục…", "Search categories…"), text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bag").font(.largeTitle).foregroundStyle(.secondary)
            Text(store.t("Chưa có danh mục sản phẩm nào.", "No product categories yet.")).foregroundStyle(.secondary)
            if store.isAdmin {
                Text(store.t("Bấm biểu tượng ⚙️ ở góc trên để thêm danh mục, sản phẩm.",
                             "Tap the ⚙️ icon at the top to add categories and products."))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let c = effectiveConfig, !c.bannerUrl.isEmpty {
                StoreMediaCarousel(media: [StoreMedia(type: c.bannerType, url: c.bannerUrl)], height: 170)
            }
            HStack(spacing: 12) {
                if let c = effectiveConfig, !c.logoUrl.isEmpty, let url = URL(string: c.logoUrl) {
                    Group {
                        if c.logoUrl.lowercased().contains(".gif") {
                            GIFWebView(url: url, contentMode: "cover")
                        } else {
                            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { Color(.secondarySystemBackground) }
                        }
                    }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "bag.fill").font(.title2).foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 2) {
                    AnimatedStoreLogo(
                        text: displayName,
                        effect: effectiveConfig?.logoEffect ?? "rainbow",
                        fontStyle: effectiveConfig?.logoFont ?? "rounded",
                        anim: effectiveConfig?.logoAnim ?? "shimmer",
                        size: 24)
                    Text({
                            let s = (config?.slogan ?? "").trimmingCharacters(in: .whitespaces)
                            return s.isEmpty ? store.t("Cửa hàng sản phẩm số · key · tải về", "Digital store · keys · downloads") : s
                         }())
                        .font(keniosFont(config?.sloganFont ?? "rounded", size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func categoryCard(_ cat: StoreCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StoreThumb(media: cat.media, height: categoryThumbHeight)
            Text(cat.name)
                .font(cardScale < 0.85 ? .caption.bold() : .subheadline.bold())
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reload() async {
        loading = true; error = nil
        URLCache.shared.removeAllCachedResponses()
        async let cfgTask = store.api.storeConfig()
        async let dlTask  = store.api.storeDownloads()
        async let ctTask  = store.api.storeContacts()
        async let catTask = store.api.storeCategories()
        if let c = try? await cfgTask {
            config = c
            // lưu cache để lần sau (kể cả khi offline) vẫn giữ tên/logo/banner
            cfgName = c.logoName; cfgLogo = c.logoUrl
            cfgBannerType = c.bannerType; cfgBannerUrl = c.bannerUrl
        }
        downloads = (try? await dlTask) ?? []
        contacts  = try? await ctTask
        if let cats = try? await catTask {
            categories = cats
            if !cats.isEmpty { storeHasData = true }
        } else if !storeHasData && categories.isEmpty {
            error = "Không kết nối được máy chủ. Kiểm tra IP/URL & mạng."
        }
        loading = false
        // Lưu số danh mục hiện tại để background task so sánh lần sau
        UserDefaults.standard.set(categories.count, forKey: "bgLastCatCount")
        // Tải toàn bộ sản phẩm ngay sau khi có danh sách danh mục
        if !categories.isEmpty { await loadAllProducts() }
    }

    private func loadAllProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        var seen = Set<Int>()
        var products: [StoreProduct] = []
        await withTaskGroup(of: [StoreProduct].self) { group in
            for cat in categories {
                group.addTask {
                    let folders = (try? await self.store.api.storeFolders(categoryId: cat.id)) ?? []
                    var catProducts: [StoreProduct] = []
                    for folder in folders {
                        let prods = (try? await self.store.api.storeProducts(folderId: folder.id)) ?? []
                        catProducts.append(contentsOf: prods)
                    }
                    return catProducts
                }
            }
            for await batch in group {
                for p in batch where !seen.contains(p.id) {
                    seen.insert(p.id)
                    products.append(p)
                }
            }
        }
        allProducts = products
        loadingProducts = false
    }
}

// ============================ Danh sách thư mục con ============================
struct StoreFolderListView: View {
    @EnvironmentObject var store: AppStore
    let category: StoreCategory
    @State private var folders: [StoreFolder] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !category.media.isEmpty {
                    StoreMediaCarousel(media: category.media, height: 170)
                }
                if loading && folders.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if folders.isEmpty {
                    Text(store.t("Chưa có thư mục con nào.", "No subfolders yet.")).foregroundStyle(.secondary)
                } else {
                    ForEach(folders) { f in
                        NavigationLink {
                            StoreProductListView(folder: f)
                        } label: {
                            HStack(spacing: 12) {
                                folderThumb(f)
                                Text(f.name).font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder private func folderThumb(_ f: StoreFolder) -> some View {
        if let m = f.media.first, m.type != "video", let url = URL(string: m.url) {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
            placeholder: { Color(.tertiarySystemBackground) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "folder.fill").foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func reload() async {
        loading = true
        folders = (try? await store.api.storeFolders(categoryId: category.id)) ?? []
        loading = false
    }
}

// ============================ Danh sách sản phẩm ============================
struct StoreProductListView: View {
    @EnvironmentObject var store: AppStore
    let folder: StoreFolder
    @State private var products: [StoreProduct] = []
    @State private var loading = false

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if loading && products.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
            } else if products.isEmpty {
                Text(store.t("Chưa có sản phẩm nào.", "No products yet.")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(products) { p in
                        NavigationLink {
                            StoreProductDetailView(productId: p.id)
                        } label: { productRow(p) }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func productRow(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StoreThumb(media: p.media, height: 130)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.subheadline.bold()).lineLimit(2)
                if let cheapest = p.prices.map(\.amount).min() {
                    Text(store.t("Từ", "From") + " \(kFormatVND(cheapest))").font(.caption.bold()).foregroundStyle(Theme.accent)
                } else {
                    Text(store.t("Chưa có giá", "No price")).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(p.availableKeys > 0 ? store.t("Còn", "Left") + " \(p.availableKeys)" : store.t("Hết hàng", "Out of stock"))
                        .font(.caption2)
                        .foregroundStyle(p.availableKeys > 0 ? .green : .red)
                    if p.isAcc {
                        Image(systemName: "gamecontroller").font(.caption2).foregroundStyle(.purple)
                    }
                    if p.hasDownload {
                        Image(systemName: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reload() async {
        loading = true
        products = (try? await store.api.storeProducts(folderId: folder.id)) ?? []
        loading = false
    }
}

// ============================ Chi tiết sản phẩm + mua ============================
struct StoreProductDetailView: View {
    @EnvironmentObject var store: AppStore
    let productId: Int

    @AppStorage("storeRecentViews") private var recentViewsRaw: String = ""
    @AppStorage("storeCartRaw") private var cartRaw: String = "[]"
    @AppStorage("productRatings") private var ratingsRaw: String = "{}"
    @State private var product: StoreProduct?
    @State private var mine: StoreProductMine?
    @State private var selectedPrice: StorePrice?
    @State private var balance: Int = 0
    @State private var loading = false
    @State private var buying = false
    @State private var error: String?
    @State private var info: String?
    @State private var showWallet = false
    @State private var contacts: StoreContacts?

    private var cartItems: [CartItem] {
        (try? JSONDecoder().decode([CartItem].self, from: Data(cartRaw.utf8))) ?? []
    }
    private func isInCart(_ id: Int) -> Bool { cartItems.contains { $0.productId == id } }
    private func addToCart(_ p: StoreProduct) {
        let price = selectedPrice ?? p.prices.first
        guard let pr = price else { return }
        var items = cartItems
        guard !items.contains(where: { $0.productId == p.id }) else { return }
        items.append(CartItem(productId: p.id, productName: p.name,
                              priceId: pr.id, priceAmount: pr.amount, priceLabel: pr.label))
        if let d = try? JSONEncoder().encode(items) { cartRaw = String(data: d, encoding: .utf8) ?? "[]" }
    }
    private var myRating: Int {
        let dict = (try? JSONDecoder().decode([String: Int].self, from: Data(ratingsRaw.utf8))) ?? [:]
        return dict["\(productId)"] ?? 0
    }
    private func saveRating(_ stars: Int) {
        var dict = (try? JSONDecoder().decode([String: Int].self, from: Data(ratingsRaw.utf8))) ?? [:]
        dict["\(productId)"] = stars
        if let d = try? JSONEncoder().encode(dict) { ratingsRaw = String(data: d, encoding: .utf8) ?? "{}" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = product {
                    StoreMediaCarousel(media: p.media, height: 220)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.title2.bold())
                            if !p.description.isEmpty {
                                Text(p.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        ShareLink(item: "\(p.name)\n\(p.description)") {
                            Image(systemName: "square.and.arrow.up")
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                    }

                    if let m = mine, m.owned {
                        ownedSection(m)
                        ratingSection
                    } else {
                        buySection(p)
                    }

                    if let c = contacts, (!c.contact.isEmpty || !c.groups.isEmpty) {
                        contactSellerSection(c)
                    }

                    if let info { Text(info).font(.footnote).foregroundStyle(.green) }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                } else if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                } else {
                    Text(store.t("Không tải được sản phẩm.", "Could not load product.")).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(product?.name ?? store.t("Sản phẩm", "Product"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload(); trackRecentView(productId) }
        .sheet(isPresented: $showWallet, onDismiss: { Task { await reloadBalance() } }) {
            StoreWalletView()
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(store.t("Đánh giá sản phẩm", "Rate this product")).font(.headline)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button { saveRating(star) } label: {
                        Image(systemName: star <= myRating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= myRating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                if myRating > 0 {
                    Text(store.t(["", "Rất tệ", "Tệ", "Bình thường", "Tốt", "Rất tốt"][myRating],
                                 ["", "Very bad", "Bad", "Okay", "Good", "Excellent"][myRating]))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func contactSellerSection(_ c: StoreContacts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label(store.t("Liên hệ người bán", "Contact seller"), systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(c.contact.filter(\.enabled)) { link in
                        if let url = URL(string: link.url) {
                            Link(destination: url) {
                                Label(link.platform, systemImage: "arrow.up.right.circle")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.accent.opacity(0.14))
                                    .foregroundStyle(Theme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    ForEach(c.groups.filter(\.enabled)) { link in
                        if let url = URL(string: link.url) {
                            Link(destination: url) {
                                Label(link.platform, systemImage: "person.3.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.purple.opacity(0.14))
                                    .foregroundStyle(Theme.purple)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func trackRecentView(_ id: Int) {
        var ids = recentViewsRaw.split(separator: ",").compactMap { Int($0) }
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > 10 { ids = Array(ids.prefix(10)) }
        recentViewsRaw = ids.map(String.init).joined(separator: ",")
    }

    // Đã mua: hiện key + nút tải game
    @ViewBuilder private func ownedSection(_ m: StoreProductMine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Bạn đã sở hữu sản phẩm này", "You already own this product"), systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if let key = m.key, !key.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(product?.itemLabel ?? "KEY") " + store.t("của bạn", "(yours)")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(key).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button { UIPasteboard.general.string = key } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                    .padding(10).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            downloadButton(url: m.downloadUrl, fileId: m.downloadFileId)
        }
        .padding().background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func downloadButton(url: String?, fileId: Int?) -> some View {
        if let url, !url.isEmpty, let u = URL(string: url) {
            Link(destination: u) {
                Label(store.t("Tải game", "Download game"), systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else if let fileId {
            StoreFileDownloadButton(fileId: fileId)
        } else if !(product?.isAcc ?? false) {
            Text(store.t("Sản phẩm chưa có bản tải. Liên hệ admin.", "This product has no download yet. Contact admin."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // Chưa mua: chọn gói thời hạn → mua bằng số dư ví (giao tức thì)
    @ViewBuilder private func buySection(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if p.prices.isEmpty {
                Text(store.t("Sản phẩm chưa có giá bán.", "This product has no price yet.")).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(store.t("Số dư ví", "Wallet balance") + ": \(kFormatVND(balance))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.t("Nạp ví", "Top up")) { showWallet = true }.font(.caption.bold())
                }

                Text(store.t("Chọn gói thời hạn", "Choose a plan")).font(.headline)
                ForEach(p.prices) { price in
                    let outOfStock = !price.inStock
                    Button {
                        if !outOfStock { selectedPrice = price }
                    } label: {
                        HStack {
                            Image(systemName: selectedPrice?.id == price.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(outOfStock ? .secondary : Theme.accent)
                            Text(price.label).foregroundStyle(outOfStock ? .secondary : .primary)
                            if outOfStock {
                                Text(store.t("Hết hàng", "Out of stock"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red.opacity(0.15)).foregroundStyle(.red)
                                    .clipShape(Capsule())
                            } else if let a = price.available, a <= 5 {
                                Text(store.t("Còn", "Left") + " \(a)")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(kFormatVND(price.amount)).bold()
                                .foregroundStyle(outOfStock ? .secondary : Theme.accent)
                                .strikethrough(outOfStock)
                        }
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(outOfStock)
                }

                // Tồn kho theo mốc đã chọn (mỗi mốc có kho riêng)
                let sel = selectedPrice ?? p.prices.first(where: { $0.inStock }) ?? p.prices.first
                let tierInStock = sel?.inStock ?? false
                let priceAmt = sel?.amount ?? 0
                let enough = balance >= priceAmt
                Button {
                    Task { await buy(p) }
                } label: {
                    HStack {
                        if buying { ProgressView().tint(.white) }
                        Text(buying ? store.t("Đang xử lý...", "Processing...")
                             : (!tierInStock ? store.t("Mốc này đã hết hàng", "This plan is out of stock")
                                : (enough ? store.t("Mua bằng số dư", "Pay with wallet") + " (\(kFormatVND(priceAmt)))"
                                          : store.t("Nạp thêm để mua", "Top up to buy"))))
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(tierInStock ? Theme.purple : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(buying || !tierInStock)

                if tierInStock && !p.prices.isEmpty {
                    Button { addToCart(p) } label: {
                        Label(isInCart(p.id) ? store.t("Đã thêm vào giỏ hàng", "Added to cart") : store.t("Thêm vào giỏ hàng", "Add to cart"),
                              systemImage: isInCart(p.id) ? "cart.badge.checkmark" : "cart.badge.plus")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isInCart(p.id))
                }

                Text(store.t("Mua bằng số dư ví — giao key/acc ngay lập tức.", "Pay with wallet balance — key/account delivered instantly."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func reload() async {
        loading = true; error = nil
        async let pTask = store.api.storeProduct(productId)
        async let cTask = store.api.storeContacts()
        do {
            let p = try await pTask
            product = p
            // Mặc định chọn mốc CÒN HÀNG đầu tiên (mỗi mốc có kho riêng)
            if selectedPrice == nil {
                selectedPrice = p.prices.first(where: { $0.inStock }) ?? p.prices.first
            }
        } catch { self.error = error.localizedDescription }
        contacts = try? await cTask
        mine = try? await store.api.storeProductMine(productId)
        await reloadBalance()
        loading = false
    }

    private func reloadBalance() async {
        if let w = try? await store.api.storeWallet() { balance = w.balance }
    }

    private func buy(_ p: StoreProduct) async {
        let priceAmt = selectedPrice?.amount ?? p.prices.first?.amount ?? 0
        if balance < priceAmt {
            info = nil; error = store.t("Số dư ví không đủ. Hãy nạp thêm vào ví.", "Insufficient wallet balance. Please top up.")
            showWallet = true
            return
        }
        buying = true; error = nil; info = nil
        do {
            let r = try await store.api.storeBuy(productId: p.id, priceId: selectedPrice?.id)
            balance = r.balance
            mine = StoreProductMine(owned: true, key: r.key,
                                    downloadUrl: r.downloadUrl, downloadFileId: r.downloadFileId)
            info = r.message
        } catch {
            self.error = error.localizedDescription
            // Có thể do hết số dư (server kiểm tra lại) → mở ví
            if (error.localizedDescription).contains("số dư") || (error.localizedDescription).contains("Số dư") {
                showWallet = true
            }
        }
        buying = false
    }

}

// Nút tải file (sản phẩm dùng file upload thay vì link)
struct StoreFileDownloadButton: View {
    @EnvironmentObject var store: AppStore
    let fileId: Int
    @State private var localURL: URL?
    @State private var downloading = false
    @State private var error: String?

    var body: some View {
        VStack {
            if let localURL {
                ShareLink(item: localURL) {
                    Label(store.t("Lưu / mở file đã tải", "Save / open downloaded file"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Button { Task { await download() } } label: {
                    HStack {
                        if downloading { ProgressView().tint(.white) }
                        Text(downloading ? store.t("Đang tải...", "Downloading...") : store.t("Tải game", "Download game"))
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(downloading)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func download() async {
        downloading = true; error = nil
        do {
            let (url, _) = try await store.api.downloadFileRaw(fileId)
            localURL = url
        } catch { self.error = error.localizedDescription }
        downloading = false
    }
}

// ============================ Đơn của tôi (khách) ============================
struct StoreMyOrdersView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var orders: [StoreOrder] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if loading && orders.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if orders.isEmpty {
                    Text(store.t("Bạn chưa mua sản phẩm nào.", "You haven't bought any products.")).foregroundStyle(.secondary)
                } else {
                    ForEach(orders) { o in orderRow(o) }
                }
            }
            .navigationTitle(store.t("Đơn của tôi", "My orders"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    @ViewBuilder private func orderRow(_ o: StoreOrder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(o.productName).font(.subheadline.bold())
                Spacer()
                Text(o.status == "completed" ? "Hoàn tất" : "Chờ thanh toán")
                    .font(.caption2)
                    .foregroundStyle(o.status == "completed" ? .green : .orange)
            }
            Text(kFormatVND(o.amount)).font(.caption).foregroundStyle(Theme.accent)
            if let key = o.key, !key.isEmpty {
                HStack {
                    Text(key).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                    Spacer()
                    Button { UIPasteboard.general.string = key } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if o.status == "completed" {
                if let url = o.downloadUrl, !url.isEmpty, let u = URL(string: url) {
                    Link(destination: u) {
                        Label(store.t("Tải game", "Download game"), systemImage: "arrow.down.circle.fill").font(.caption.bold())
                    }
                } else if let fid = o.downloadFileId {
                    StoreFileDownloadButton(fileId: fid)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        loading = true
        orders = (try? await store.api.storeMyOrders()) ?? []
        loading = false
    }
}

// Nút mở bảng tuỳ chỉnh giao diện + ngôn ngữ (dùng chung — áp cho toàn app)
struct AppearanceMenu: View {
    @EnvironmentObject var store: AppStore
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "paintbrush.pointed.fill")
        }
        .sheet(isPresented: $show) { AppearanceSheet().environmentObject(store) }
    }
}

// Bảng tuỳ chỉnh đẹp: chọn Giao diện (thẻ) + Ngôn ngữ (lưới có cờ)
struct AppearanceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let langCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // ----- Giao diện -----
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.t("Giao diện", "Theme"), systemImage: "circle.lefthalf.filled")
                            .font(.headline)
                        HStack(spacing: 12) {
                            themeCard("light",  store.t("Sáng", "Light"),  "sun.max.fill",     [.orange, .yellow])
                            themeCard("dark",   store.t("Tối", "Dark"),    "moon.stars.fill",  [.indigo, .purple])
                            themeCard("system", store.t("Tự động", "Auto"), "circle.lefthalf.filled", [.blue, .cyan])
                        }
                    }

                    // ----- Ngôn ngữ -----
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.t("Ngôn ngữ", "Language"), systemImage: "globe")
                            .font(.headline)
                        LazyVGrid(columns: langCols, spacing: 10) {
                            ForEach(kAppLanguages, id: \.0) { code, name in
                                langCard(code, name)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(store.t("Tuỳ chỉnh giao diện", "Appearance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Xong", "Done")) { dismiss() }.bold()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func themeCard(_ mode: String, _ title: String, _ icon: String, _ colors: [Color]) -> some View {
        let on = store.themeMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { store.setThemeMode(mode) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on ? store.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(store.accentColor).padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func langCard(_ code: String, _ name: String) -> some View {
        let on = store.language == code
        return Button {
            store.setLanguage(code)
        } label: {
            HStack(spacing: 6) {
                Text(name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 2)
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(store.accentColor) }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? store.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(on ? store.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// ============================ Tìm kiếm toàn cục trong cửa hàng ============================
struct StoreGlobalSearchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let categories: [StoreCategory]

    @State private var query = ""
    @State private var folders: [StoreFolder] = []
    @State private var products: [StoreProduct] = []
    @State private var loading = false

    private var matchingCategories: [StoreCategory] {
        guard !query.isEmpty else { return [] }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }

                if !matchingCategories.isEmpty {
                    Section(store.t("Danh mục", "Categories") + " (\(matchingCategories.count))") {
                        ForEach(matchingCategories) { cat in
                            NavigationLink(cat.name) {
                                StoreFolderListView(category: cat)
                            }
                        }
                    }
                }

                let matchFolders = folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
                if !matchFolders.isEmpty {
                    Section(store.t("Thư mục", "Folders") + " (\(matchFolders.count))") {
                        ForEach(matchFolders) { f in
                            NavigationLink(f.name) {
                                StoreProductListView(folder: f)
                            }
                        }
                    }
                }

                let matchProducts = products.filter { p in
                    p.name.localizedCaseInsensitiveContains(query) ||
                    p.description.localizedCaseInsensitiveContains(query)
                }
                if !matchProducts.isEmpty {
                    Section(store.t("Sản phẩm", "Products") + " (\(matchProducts.count))") {
                        ForEach(matchProducts) { p in
                            NavigationLink {
                                StoreProductDetailView(productId: p.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).font(.subheadline.bold())
                                    if let cheapest = p.prices.map(\.amount).min() {
                                        Text(store.t("Từ", "From") + " \(kFormatVND(cheapest))")
                                            .font(.caption).foregroundStyle(Theme.accent)
                                    }
                                    HStack {
                                        Text(p.availableKeys > 0 ? store.t("Còn", "Left") + " \(p.availableKeys)" : store.t("Hết hàng", "Out of stock"))
                                            .font(.caption2)
                                            .foregroundStyle(p.availableKeys > 0 ? .green : .red)
                                    }
                                }
                            }
                        }
                    }
                }

                if !loading && !query.isEmpty && matchingCategories.isEmpty &&
                    folders.filter({ $0.name.localizedCaseInsensitiveContains(query) }).isEmpty &&
                    products.filter({ $0.name.localizedCaseInsensitiveContains(query) }).isEmpty {
                    Text(store.t("Không tìm thấy kết quả nào cho", "No results found for") + " \"\(query)\".")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                if query.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text(store.t("Nhập tên sản phẩm, danh mục hoặc thư mục để tìm kiếm.",
                                     "Type a product, category, or folder name to search."))
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(store.t("Tìm kiếm", "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: store.t("Tìm sản phẩm, danh mục...", "Search products, categories..."))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await loadAll() }
            .onChange(of: query) { _ in }
        }
    }

    private func loadAll() async {
        loading = true
        var allFolders: [StoreFolder] = []
        var allProducts: [StoreProduct] = []
        for cat in categories {
            let flds = (try? await store.api.storeFolders(categoryId: cat.id)) ?? []
            allFolders.append(contentsOf: flds)
            for f in flds {
                let prods = (try? await store.api.storeProducts(folderId: f.id)) ?? []
                allProducts.append(contentsOf: prods)
            }
        }
        folders = allFolders
        products = allProducts
        loading = false
    }
}

// ============================ Giỏ hàng ============================
struct StoreCartView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("storeCartRaw") private var cartRaw: String = "[]"
    @State private var balance: Int = 0
    @State private var buying = false
    @State private var progress = ""
    @State private var message: String?
    @State private var isError = false
    @State private var showWallet = false
    @State private var promoCode = ""
    @State private var promoResult: PromoValidateResult?
    @State private var promoError = ""
    @State private var validatingPromo = false

    private var cartItems: [CartItem] {
        (try? JSONDecoder().decode([CartItem].self, from: Data(cartRaw.utf8))) ?? []
    }
    private var rawTotal: Int { cartItems.reduce(0) { $0 + $1.priceAmount } }
    private var discount: Int { promoResult?.discount ?? 0 }
    private var total: Int { max(0, rawTotal - discount) }

    private func removeItem(_ id: UUID) {
        var items = cartItems; items.removeAll { $0.id == id }
        if let d = try? JSONEncoder().encode(items) { cartRaw = String(data: d, encoding: .utf8) ?? "[]" }
        promoResult = nil; promoError = ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if cartItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cart").font(.system(size: 60)).foregroundStyle(.secondary)
                        Text(store.t("Giỏ hàng trống", "Cart is empty")).font(.title3.bold())
                        Text(store.t("Bấm 'Thêm vào giỏ' ở trang chi tiết sản phẩm để mua nhiều cùng lúc.",
                                     "Tap 'Add to cart' on a product page to buy several at once."))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(store.t("Sản phẩm", "Products") + " (\(cartItems.count))") {
                            ForEach(cartItems) { item in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.productName).font(.subheadline.bold()).lineLimit(2)
                                        Text(item.priceLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(kFormatVND(item.priceAmount))
                                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                                    Button { removeItem(item.id) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Section(store.t("Mã khuyến mãi", "Promo code")) {
                            HStack(spacing: 8) {
                                TextField(store.t("Nhập mã giảm giá...", "Enter discount code..."), text: $promoCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .onSubmit { Task { await applyPromo() } }
                                if validatingPromo {
                                    ProgressView().scaleEffect(0.8)
                                } else if promoResult != nil {
                                    Button { promoResult = nil; promoCode = ""; promoError = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                    }.buttonStyle(.borderless)
                                } else {
                                    Button(store.t("Áp dụng", "Apply")) { Task { await applyPromo() } }
                                        .font(.caption.bold())
                                        .disabled(promoCode.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                            if let r = promoResult {
                                Label(store.t("Giảm", "Off") + " \(r.label) — " + store.t("tiết kiệm", "save") + " \(kFormatVND(discount))", systemImage: "checkmark.seal.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            if !promoError.isEmpty {
                                Text(promoError).font(.caption).foregroundStyle(.red)
                            }
                        }

                        Section {
                            if discount > 0 {
                                HStack {
                                    Text(store.t("Giá gốc", "Subtotal")).font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(kFormatVND(rawTotal)).font(.subheadline).strikethrough().foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(store.t("Giảm giá", "Discount")).font(.subheadline).foregroundStyle(.green)
                                    Spacer()
                                    Text("-\(kFormatVND(discount))").font(.subheadline.bold()).foregroundStyle(.green)
                                }
                            }
                            HStack {
                                Text(store.t("Tổng cộng", "Total")).font(.headline)
                                Spacer()
                                Text(kFormatVND(total)).font(.headline.bold()).foregroundStyle(Theme.accent)
                            }
                            HStack {
                                Text(store.t("Số dư ví", "Wallet balance") + ": \(kFormatVND(balance))").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(store.t("Nạp ví", "Top up")) { showWallet = true }.font(.caption.bold())
                            }
                            Button {
                                Task { await checkout() }
                            } label: {
                                HStack {
                                    if buying { ProgressView().tint(.white).padding(.trailing, 4) }
                                    Text(buying ? store.t("Đang thanh toán...", "Paying...")
                                         : (balance >= total ? store.t("Thanh toán", "Pay") + " \(kFormatVND(total))" : store.t("Số dư không đủ — Nạp ví", "Insufficient balance — Top up")))
                                }
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(balance >= total && !buying ? Theme.purple : Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(buying)
                        }

                        if !progress.isEmpty {
                            Section { Text(progress).font(.caption).foregroundStyle(.secondary) }
                        }
                        if let message {
                            Section { Text(message).foregroundStyle(isError ? .red : .green).font(.footnote) }
                        }
                    }
                }
            }
            .navigationTitle(store.t("Giỏ hàng", "Cart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !cartItems.isEmpty {
                        Button(store.t("Xoá hết", "Clear all"), role: .destructive) { cartRaw = "[]" }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } }
            }
            .task { await reloadBalance() }
            .sheet(isPresented: $showWallet, onDismiss: { Task { await reloadBalance() } }) { StoreWalletView() }
        }
    }

    private func applyPromo() async {
        let code = promoCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        validatingPromo = true; promoError = ""; promoResult = nil
        do {
            let r = try await store.api.storeValidatePromo(code: code, amount: rawTotal)
            promoResult = r
        } catch {
            promoError = error.localizedDescription
        }
        validatingPromo = false
    }

    private func reloadBalance() async {
        if let w = try? await store.api.storeWallet() { balance = w.balance }
    }

    private func checkout() async {
        buying = true; isError = false; message = nil
        let items = cartItems
        let code = promoResult != nil ? promoCode.trimmingCharacters(in: .whitespaces) : nil
        var successCount = 0
        for item in items {
            progress = "Đang mua: \(item.productName)..."
            if (try? await store.api.storeBuy(productId: item.productId, priceId: item.priceId, promoCode: code)) != nil {
                removeItem(item.id)
                successCount += 1
            }
        }
        progress = ""
        let remaining = cartItems.count
        if remaining == 0 {
            isError = false; message = "Mua thành công \(successCount) sản phẩm!"
        } else {
            isError = true
            message = "Thành công: \(successCount). Thất bại: \(remaining) (hết hàng hoặc số dư không đủ)."
        }
        await reloadBalance()
        buying = false
    }
}

// Danh sách ngôn ngữ hỗ trợ
let kAppLanguages: [(String, String)] = [
    ("vi", "🇻🇳 Tiếng Việt"),
    ("en", "🇺🇸 English"),
    ("zh", "🇨🇳 中文 (简体)"),
    ("ko", "🇰🇷 한국어"),
    ("ja", "🇯🇵 日本語"),
    ("th", "🇹🇭 ภาษาไทย"),
    ("fr", "🇫🇷 Français"),
    ("es", "🇪🇸 Español"),
    ("de", "🇩🇪 Deutsch"),
    ("pt", "🇧🇷 Português"),
    ("ru", "🇷🇺 Русский"),
    ("id", "🇮🇩 Bahasa Indonesia"),
    ("ar", "🇸🇦 العربية"),
    ("hi", "🇮🇳 हिन्दी"),
]
