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

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filteredCategories: [StoreCategory] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storeHeader

                    walletBar

                    if !downloads.isEmpty {
                        downloadsSection
                    }

                    if !allProducts.isEmpty {
                        allProductsSection
                    }

                    if !wishlistProducts.isEmpty {
                        wishlistSection
                    }

                    if !recentProducts.isEmpty {
                        recentlyViewedSection
                    }

                    if !categories.isEmpty {
                        searchField
                    }

                    if loading && categories.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                    } else if categories.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(filteredCategories) { cat in
                                NavigationLink {
                                    StoreFolderListView(category: cat)
                                } label: {
                                    categoryCard(cat)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let c = contacts, (!c.contact.isEmpty || !c.groups.isEmpty) {
                        StoreContactsBlock(contacts: c)
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(config?.logoName ?? "Cửa hàng")
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
                Text("Ví cửa hàng").font(.subheadline.bold())
                if let pct = config?.topupBonusPercent, pct > 0 {
                    Text("KM +\(pct)%").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pink.opacity(0.2)).foregroundStyle(.pink)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Nạp tiền").font(.caption).foregroundStyle(Theme.accent)
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
            Label("Tải về", systemImage: "arrow.down.circle.fill").font(.headline)
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
                        Label("Tải", systemImage: "arrow.down.circle")
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
            HStack {
                Label("Tất cả sản phẩm", systemImage: "bag.fill")
                    .font(.headline)
                Spacer()
                Text("\(allProducts.count) sản phẩm")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allProducts) { product in
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
                StoreThumb(media: p.media, height: 100)
                Button { toggleWishlist(p.id) } label: {
                    Image(systemName: wishlistIds.contains(p.id) ? "heart.fill" : "heart")
                        .font(.caption.bold())
                        .foregroundStyle(wishlistIds.contains(p.id) ? .red : .white)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(p.name)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !p.prices.isEmpty {
                    Text(kFormatVND(p.prices[0].amount))
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                    Text("Tải xuống")
                        .font(.caption2.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.13))
                .foregroundStyle(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(8)
        }
        .frame(width: 150)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Yêu thích", systemImage: "heart.fill")
                    .font(.headline).foregroundStyle(.red)
                Spacer()
                Text("\(wishlistProducts.count) sản phẩm")
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
            Label("Đã xem gần đây", systemImage: "clock.arrow.circlepath")
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
            TextField("Tìm danh mục…", text: $search)
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
            Text("Chưa có danh mục sản phẩm nào.").foregroundStyle(.secondary)
            if store.isAdmin {
                Text("Bấm biểu tượng ⚙️ ở góc trên để thêm danh mục, sản phẩm.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let c = config, !c.bannerUrl.isEmpty {
                StoreMediaCarousel(media: [StoreMedia(type: c.bannerType, url: c.bannerUrl)], height: 170)
            }
            HStack(spacing: 12) {
                if let c = config, !c.logoUrl.isEmpty, let url = URL(string: c.logoUrl) {
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
                    Text(config?.logoName ?? "KENIOS Store").font(.title3.bold())
                    Text("Cửa hàng sản phẩm số · key · tải về").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func categoryCard(_ cat: StoreCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StoreThumb(media: cat.media, height: 120)
            Text(cat.name)
                .font(.subheadline.bold())
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
        config    = try? await cfgTask
        downloads = (try? await dlTask) ?? []
        contacts  = try? await ctTask
        do { categories = try await catTask }
        catch { self.error = error.localizedDescription }
        loading = false
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
                    Text("Chưa có thư mục con nào.").foregroundStyle(.secondary)
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
                Text("Chưa có sản phẩm nào.").foregroundStyle(.secondary)
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
                    Text("Từ \(kFormatVND(cheapest))").font(.caption.bold()).foregroundStyle(Theme.accent)
                } else {
                    Text("Chưa có giá").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(p.availableKeys > 0 ? "Còn \(p.availableKeys)" : "Hết hàng")
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
    @State private var product: StoreProduct?
    @State private var mine: StoreProductMine?
    @State private var selectedPrice: StorePrice?
    @State private var balance: Int = 0
    @State private var loading = false
    @State private var buying = false
    @State private var error: String?
    @State private var info: String?
    @State private var showWallet = false

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
                    } else {
                        buySection(p)
                    }

                    if let info { Text(info).font(.footnote).foregroundStyle(.green) }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                } else if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                } else {
                    Text("Không tải được sản phẩm.").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(product?.name ?? "Sản phẩm")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload(); trackRecentView(productId) }
        .sheet(isPresented: $showWallet, onDismiss: { Task { await reloadBalance() } }) {
            StoreWalletView()
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
            Label("Bạn đã sở hữu sản phẩm này", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if let key = m.key, !key.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(product?.itemLabel ?? "KEY") của bạn").font(.caption).foregroundStyle(.secondary)
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
                Label("Tải game", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else if let fileId {
            StoreFileDownloadButton(fileId: fileId)
        } else if !(product?.isAcc ?? false) {
            Text("Sản phẩm chưa có bản tải. Liên hệ admin.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // Chưa mua: chọn gói thời hạn → mua bằng số dư ví (giao tức thì)
    @ViewBuilder private func buySection(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if p.prices.isEmpty {
                Text("Sản phẩm chưa có giá bán.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Số dư ví: \(kFormatVND(balance))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Nạp ví") { showWallet = true }.font(.caption.bold())
                }

                Text("Chọn gói thời hạn").font(.headline)
                ForEach(p.prices) { price in
                    Button {
                        selectedPrice = price
                    } label: {
                        HStack {
                            Image(systemName: selectedPrice?.id == price.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(Theme.accent)
                            Text(price.label)
                            Spacer()
                            Text(kFormatVND(price.amount)).bold().foregroundStyle(Theme.accent)
                        }
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                let priceAmt = selectedPrice?.amount ?? p.prices.first?.amount ?? 0
                let enough = balance >= priceAmt
                Button {
                    Task { await buy(p) }
                } label: {
                    HStack {
                        if buying { ProgressView().tint(.white) }
                        Text(buying ? "Đang xử lý..."
                             : (p.availableKeys <= 0 ? "Tạm hết hàng"
                                : (enough ? "Mua bằng số dư (\(kFormatVND(priceAmt)))" : "Nạp thêm để mua")))
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(p.availableKeys > 0 ? Theme.purple : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(buying || p.availableKeys <= 0)

                Text("Mua bằng số dư ví — giao key/acc ngay lập tức.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func reload() async {
        loading = true; error = nil
        do {
            let p = try await store.api.storeProduct(productId)
            product = p
            if selectedPrice == nil { selectedPrice = p.prices.first }
        } catch { self.error = error.localizedDescription }
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
            info = nil; error = "Số dư ví không đủ. Hãy nạp thêm vào ví."
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
                    Label("Lưu / mở file đã tải", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Button { Task { await download() } } label: {
                    HStack {
                        if downloading { ProgressView().tint(.white) }
                        Text(downloading ? "Đang tải..." : "Tải game")
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
                    Text("Bạn chưa mua sản phẩm nào.").foregroundStyle(.secondary)
                } else {
                    ForEach(orders) { o in orderRow(o) }
                }
            }
            .navigationTitle("Đơn của tôi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
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
                        Label("Tải game", systemImage: "arrow.down.circle.fill").font(.caption.bold())
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

// Menu đổi giao diện sáng/tối/tự động + ngôn ngữ (dùng chung — áp cho toàn app)
struct AppearanceMenu: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Menu {
            Menu("Giao diện") {
                Button { store.setThemeMode("light") } label: {
                    Label("Sáng", systemImage: store.themeMode == "light" ? "checkmark" : "sun.max")
                }
                Button { store.setThemeMode("dark") } label: {
                    Label("Tối", systemImage: store.themeMode == "dark" ? "checkmark" : "moon")
                }
                Button { store.setThemeMode("system") } label: {
                    Label("Tự động (cân bằng)", systemImage: store.themeMode == "system" ? "checkmark" : "circle.lefthalf.filled")
                }
            }
            Menu("Ngôn ngữ") {
                ForEach(kAppLanguages, id: \.0) { code, name in
                    Button { store.setLanguage(code) } label: {
                        Label(name, systemImage: store.language == code ? "checkmark" : "globe")
                    }
                }
            }
        } label: {
            Image(systemName: "paintbrush")
        }
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
                    Section("Danh mục (\(matchingCategories.count))") {
                        ForEach(matchingCategories) { cat in
                            NavigationLink(cat.name) {
                                StoreFolderListView(category: cat)
                            }
                        }
                    }
                }

                let matchFolders = folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
                if !matchFolders.isEmpty {
                    Section("Thư mục (\(matchFolders.count))") {
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
                    Section("Sản phẩm (\(matchProducts.count))") {
                        ForEach(matchProducts) { p in
                            NavigationLink {
                                StoreProductDetailView(productId: p.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).font(.subheadline.bold())
                                    if let cheapest = p.prices.map(\.amount).min() {
                                        Text("Từ \(kFormatVND(cheapest))")
                                            .font(.caption).foregroundStyle(Theme.accent)
                                    }
                                    HStack {
                                        Text(p.availableKeys > 0 ? "Còn \(p.availableKeys)" : "Hết hàng")
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
                    Text("Không tìm thấy kết quả nào cho \"\(query)\".")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                if query.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Nhập tên sản phẩm, danh mục hoặc thư mục để tìm kiếm.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Tìm kiếm")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm sản phẩm, danh mục...")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
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

// Danh sách ngôn ngữ (đa ngôn ngữ)
let kAppLanguages: [(String, String)] = [
    ("vi", "Tiếng Việt"),
    ("en", "English"),
    ("zh", "中文"),
    ("ko", "한국어"),
    ("ja", "日本語"),
    ("th", "ไทย"),
    ("fr", "Français"),
    ("es", "Español"),
]
