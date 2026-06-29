import SwiftUI
import AVKit
import WebKit

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
    @State private var productsByCategory: [Int: [StoreProduct]] = [:]
    @State private var loadingProducts = false
    @AppStorage("storeWishlist") private var wishlistRaw: String = ""
    @AppStorage("storeRecentViews") private var recentViewsRaw: String = ""
    // Cache cấu hình cửa hàng — giữ tên/logo/banner khi mất kết nối, không bị reset về mặc định
    @AppStorage("storeCfgName") private var cfgName: String = ""
    @AppStorage("storeCfgLogo") private var cfgLogo: String = ""
    @AppStorage("storeCfgLogoType") private var cfgLogoType: String = "image"
    @AppStorage("storeCfgBannerType") private var cfgBannerType: String = "image"
    @AppStorage("storeCfgBannerUrl") private var cfgBannerUrl: String = ""
    // Cache thứ tự + mục ẩn để render đầu tiên giữ đúng bố cục (không nhảy khi config tải xong)
    @AppStorage("storeCfgSectionOrder") private var cfgSectionOrder: String = ""
    @AppStorage("storeCfgSectionHidden") private var cfgSectionHidden: String = ""
    @State private var storeHasData: Bool = false
    @State private var productSort: String = "default"  // default | priceAsc | priceDesc | name
    @State private var productFilter: String = "all"    // all | inStock
    @State private var showCart = false
    @State private var showContacts = false
    @AppStorage("storeCartRaw") private var cartRaw: String = "[]"
    @State private var showcase: StoreShowcase?
    @State private var scrollTarget: String?   // dùng cho ScrollViewReader scroll đến section
    @State private var flashNow = Date()   // cập nhật để đồng hồ flash sale đếm ngược
    @State private var showcaseTick: Int = 0   // tăng mỗi 5 phút → xoay vòng showcase
    private let flashTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let showcaseTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    // (Dải giao dịch/nạp tiền tự cuộn 5 giây nằm trong AutoScrollTicker — không
    //  còn timer ở đây để khỏi kéo cả cửa hàng vẽ lại gây nháy.)

    // Tên hiển thị trong showcase — 200 tên Việt Nam không lặp
    private let showcaseNames: [String] = [
        "Nguyễn Văn M","Nguyễn Thị H","Nguyễn Văn T","Nguyễn Thị L","Nguyễn Văn A",
        "Nguyễn Thị N","Nguyễn Văn Ph","Nguyễn Thị Tr","Nguyễn Văn Kh","Nguyễn Thị B",
        "Trần Văn H","Trần Thị M","Trần Văn L","Trần Thị A","Trần Văn T",
        "Trần Thị K","Trần Văn S","Trần Thị P","Trần Văn D","Trần Thị V",
        "Lê Văn T","Lê Thị H","Lê Văn N","Lê Thị M","Lê Văn B",
        "Lê Thị Q","Lê Văn C","Lê Thị D","Lê Văn Ph","Lê Thị Tr",
        "Phạm Văn H","Phạm Thị L","Phạm Văn T","Phạm Thị N","Phạm Văn A",
        "Phạm Thị K","Phạm Văn S","Phạm Thị B","Phạm Văn G","Phạm Thị X",
        "Hoàng Văn M","Hoàng Thị T","Hoàng Văn L","Hoàng Thị A","Hoàng Văn N",
        "Hoàng Thị K","Hoàng Văn C","Hoàng Thị P","Hoàng Văn D","Hoàng Thị V",
        "Huỳnh Văn T","Huỳnh Thị H","Huỳnh Văn N","Huỳnh Thị M","Huỳnh Văn A",
        "Huỳnh Thị B","Huỳnh Văn Kh","Huỳnh Thị L","Huỳnh Văn S","Huỳnh Thị P",
        "Phan Văn H","Phan Thị T","Phan Văn M","Phan Thị N","Phan Văn L",
        "Phan Thị K","Phan Văn D","Phan Thị V","Phan Văn G","Phan Thị X",
        "Vũ Văn T","Vũ Thị H","Vũ Văn N","Vũ Thị M","Vũ Văn A",
        "Vũ Thị L","Vũ Văn B","Vũ Thị K","Vũ Văn S","Vũ Thị P",
        "Võ Văn M","Võ Thị T","Võ Văn H","Võ Thị N","Võ Văn L",
        "Võ Thị A","Võ Văn K","Võ Thị D","Võ Văn G","Võ Thị V",
        "Đặng Văn T","Đặng Thị H","Đặng Văn M","Đặng Thị L","Đặng Văn N",
        "Đặng Thị B","Đặng Văn K","Đặng Thị P","Đặng Văn S","Đặng Thị X",
        "Bùi Văn H","Bùi Thị T","Bùi Văn L","Bùi Thị M","Bùi Văn A",
        "Bùi Thị N","Bùi Văn C","Bùi Thị K","Bùi Văn D","Bùi Thị V",
        "Đỗ Văn T","Đỗ Thị H","Đỗ Văn N","Đỗ Thị M","Đỗ Văn L",
        "Đỗ Thị A","Đỗ Văn B","Đỗ Thị K","Đỗ Văn S","Đỗ Thị P",
        "Hồ Văn M","Hồ Thị T","Hồ Văn H","Hồ Thị N","Hồ Văn L",
        "Hồ Thị A","Hồ Văn G","Hồ Thị K","Hồ Văn D","Hồ Thị V",
        "Ngô Văn T","Ngô Thị H","Ngô Văn M","Ngô Thị L","Ngô Văn N",
        "Ngô Thị B","Ngô Văn K","Ngô Thị P","Ngô Văn S","Ngô Thị X",
        "Dương Văn H","Dương Thị T","Dương Văn L","Dương Thị M","Dương Văn A",
        "Dương Thị N","Dương Văn C","Dương Thị K","Dương Văn D","Dương Thị V",
        "Lý Văn T","Lý Thị H","Lý Văn N","Lý Thị M","Lý Văn A",
        "Lý Thị L","Lý Văn B","Lý Thị K","Lý Văn S","Lý Thị P",
        "Đinh Văn M","Đinh Thị T","Đinh Văn H","Đinh Thị N","Đinh Văn L",
        "Đinh Thị A","Đinh Văn K","Đinh Thị D","Đinh Văn G","Đinh Thị V",
        "Trương Văn T","Trương Thị H","Trương Văn M","Trương Thị L","Trương Văn N",
        "Trương Thị B","Trương Văn K","Trương Thị P","Trương Văn S","Trương Thị X",
        "Lâm Văn H","Lâm Thị T","Lâm Văn L","Lâm Thị M","Lâm Văn A",
        "Lâm Thị N","Lâm Văn C","Lâm Thị K","Lâm Văn D","Lâm Thị V",
        "Cao Văn T","Cao Thị H","Cao Văn N","Cao Thị M","Cao Văn L",
        "Cao Thị A","Cao Văn B","Cao Thị K","Cao Văn S","Cao Thị P",
    ]

    // Tự sinh từ sản phẩm thật, xoay vòng theo tick (5 phút/lần)
    private var effectiveShowcase: StoreShowcase {
        // Luôn có sẵn dữ liệu ảo. Mục nào server có giao dịch THẬT thì ưu tiên hiển thị thật,
        // mục nào server rỗng (cửa hàng mới / mất kết nối) thì dùng ảo để không bao giờ trống.
        let fake = generatedShowcase
        guard let s = showcase else { return fake }
        return StoreShowcase(
            recentOrders: s.recentOrders.isEmpty ? fake.recentOrders : s.recentOrders,
            recentTopups: s.recentTopups.isEmpty ? fake.recentTopups : s.recentTopups,
            leaderboard:  s.leaderboard.isEmpty  ? fake.leaderboard  : s.leaderboard)
    }

    // Dữ liệu showcase ảo — xoay vòng mỗi 5 phút theo showcaseTick
    private var generatedShowcase: StoreShowcase {
        let now = Int(Date().timeIntervalSince1970)
        let tick = showcaseTick

        // Danh sách sản phẩm cố định (ảo — xoay vòng khi chưa có giao dịch thật)
        let combos: [(String, Int)] = [
            ("VINGOLD tháng", 500_000), ("VINGOLD tuần", 250_000), ("VINGOLD ngày",  60_000),
            ("KINGMOD tháng", 900_000), ("KINGMOD tuần", 450_000), ("KINGMOD ngày", 200_000),
            ("DRACULA tháng", 500_000), ("DRACULA tuần", 250_000), ("DRACULA ngày",  70_000),
            ("OASIS tháng",   800_000), ("OASIS tuần",   400_000), ("OASIS ngày",   200_000),
            ("Liên Quân acc", 150_000), ("PUBG Mobile acc", 200_000), ("Free Fire acc", 120_000),
        ]

        // Sinh tên Việt từ Họ × Đệm × Chữ cái → 20×20×18 = 7.200 tên KHÁC NHAU (không trùng),
        // đủ cho pool 1.000+ dòng mà không phải liệt kê tay.
        let HO  = ["Nguyễn","Trần","Lê","Phạm","Hoàng","Huỳnh","Phan","Vũ","Võ","Đặng",
                   "Bùi","Đỗ","Hồ","Ngô","Dương","Lý","Đào","Đinh","Tô","Trương"]
        let DEM = ["Văn","Thị","Hữu","Đức","Minh","Quang","Thanh","Ngọc","Gia","Hoài",
                   "Tuấn","Bảo","Khánh","Nhật","Anh","Hải","Trung","Công","Xuân","Phú"]
        let CHU = ["A","B","C","D","Đ","G","H","K","L","M","N","P","Q","S","T","V","X","Y"]
        let nameSpace = HO.count * DEM.count * CHU.count
        func name(_ seed: Int) -> String {
            let s = ((seed % nameSpace) + nameSpace) % nameSpace
            let h = HO[s % HO.count]
            let d = DEM[(s / HO.count) % DEM.count]
            let c = CHU[(s / (HO.count * DEM.count)) % CHU.count]
            return "\(h) \(d) \(c)***"
        }

        // Pool 1.000 dòng (mỗi dòng 1 tên khác nhau) để ticker tự cuộn lên 5 giây/lần,
        // hết 1.000 tên thì tự lặp lại từ đầu. Mỗi 5 phút (tick) sản phẩm/số tiền đổi cho mới.
        let poolSize = 1000
        let orders: [ShowcaseOrder] = (0..<poolSize).map { i in
            let ci = (i + tick) % combos.count
            return ShowcaseOrder(
                user: name(i),
                product: combos[ci].0,
                label: "Thành công",
                amount: combos[ci].1,
                at: now - (i * 37 + 20)
            )
        }

        // Topup xoay theo tick lệch pha — 30 mức số tiền khác nhau
        let topupAmounts = [
            50_000, 100_000, 150_000, 200_000, 250_000, 300_000, 350_000, 400_000,
            450_000, 500_000, 600_000, 700_000, 800_000, 900_000, 1_000_000,
            1_200_000, 1_500_000, 2_000_000, 2_500_000, 3_000_000,
            60_000, 120_000, 180_000, 220_000, 280_000, 320_000, 380_000,
            750_000, 850_000, 950_000,
        ]
        let topups: [ShowcaseTopup] = (0..<poolSize).map { i in
            let ai = (i * 3 + tick) % topupAmounts.count
            return ShowcaseTopup(
                user: name(i + 97),   // lệch pha để tên khác phần giao dịch
                amount: topupAmounts[ai],
                at: now - (i * 43 + 25)
            )
        }

        // Leaderboard
        let leaders: [ShowcaseLeader] = (0..<5).map { i in
            let total = [5_200_000, 3_800_000, 2_900_000, 1_750_000, 980_000][(tick + i) % 5]
            return ShowcaseLeader(rank: i + 1, user: name(tick * 3 + i * 13), total: total)
        }

        return StoreShowcase(recentOrders: orders, recentTopups: topups, leaderboard: leaders)
    }

    private var displayName: String {
        if let n = config?.logoName, !n.isEmpty { return n }
        return cfgName.isEmpty ? "KENIOS STORE" : cfgName
    }
    // Cấu hình hiệu lực: ưu tiên server, fallback cache (để banner/logo không biến mất khi offline)
    private var effectiveConfig: StoreAppConfig? {
        if let c = config { return c }
        if cfgName.isEmpty && cfgLogo.isEmpty && cfgBannerUrl.isEmpty { return nil }
        return StoreAppConfig(logoName: cfgName, logoUrl: cfgLogo,
                              logoType: cfgLogoType,
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
        // Thứ tự mặc định gọn gàng, ưu tiên thấy sản phẩm ngay
        let all = ["announce", "categories", "gamecat", "flash", "trust", "steps", "leaderboard",
                   "transactions", "topups", "downloads", "contacts", "wishlist", "recent", "products", "footer"]
        let hiddenRaw = config?.sectionHidden ?? (cfgSectionHidden.isEmpty ? "" : cfgSectionHidden)
        let hidden = Set(hiddenRaw
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        let cachedOrder = cfgSectionOrder.isEmpty ? nil : cfgSectionOrder
        guard let raw = (config?.sectionOrder ?? cachedOrder), !raw.isEmpty else {
            return all.filter { !hidden.contains($0) }
        }
        let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        var merged = parts.filter { all.contains($0) }
        // Chèn các mục mới (chưa có trong cấu hình cũ) vào đúng vị trí ưu tiên thay vì dồn cuối
        for (i, k) in all.enumerated() where !merged.contains(k) {
            merged.insert(k, at: min(i, merged.count))
        }
        return merged.filter { !hidden.contains($0) }
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
            if !downloads.isEmpty || !downloadableProducts.isEmpty { downloadsSection }
        case "contacts":
            if let c = contacts, (!c.contact.isEmpty || !c.groups.isEmpty) {
                StoreContactsBlock(contacts: c)
            }
        case "wishlist":
            if !wishlistProducts.isEmpty { wishlistSection }
        case "recent":
            if !recentProducts.isEmpty { recentlyViewedSection }
        case "trust":
            trustBadgesSection
        case "steps":
            statsSection
        case "flash":
            if let p = flashProduct { flashSection(p) }
        case "leaderboard":
            leaderboardSection(effectiveShowcase.leaderboard)
        case "transactions":
            transactionsSection(effectiveShowcase.recentOrders)
        case "topups":
            topupsSection(effectiveShowcase.recentTopups)
        case "hero":
            // Hero đã được GỘP vào storeHeader (1 khối duy nhất) → không hiện riêng nữa.
            EmptyView()
        case "gamecat":
            if !productsByCategory.isEmpty { gameCatSection }
        case "announce":
            if (config?.announceEnabled ?? false),
               let txt = config?.announceText, !txt.trimmingCharacters(in: .whitespaces).isEmpty {
                announceBar(txt)
            }
        case "footer":
            footerSection
        default:
            EmptyView()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 16) {
                        storeHeader
                        walletBar
                        // Các mục hiển thị ĐÚNG theo thứ tự admin đã sắp xếp (kể cả "Tải về").
                        // Gắn .id cho mục cần cuộn đến: "products" (nút Mua ngay → Tất cả sản phẩm),
                        // "gamecat", "downloads". Gắn .id cho mọi mục dễ khiến ScrollView nhảy khi tải lại.
                        ForEach(orderedSections, id: \.self) { key in
                            if key == "products" || key == "gamecat" || key == "downloads" {
                                sectionView(key).id(key)
                            } else {
                                sectionView(key)
                            }
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .onChange(of: scrollTarget) { target in
                        if let t = target {
                            withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(t, anchor: .top) }
                            scrollTarget = nil
                        }
                    }
                }
            }
            .background {
                if let c = effectiveConfig, let bt = c.bgType, bt != "none",
                   let bu = c.bgUrl, !bu.isEmpty {
                    ZStack {
                        // .id(bu): chỉ tạo lại khi ĐỔI URL → không nạp lại/nhấp nháy mỗi lần trang vẽ lại
                        StoreBackground(type: bt, url: bu).id(bu)
                        // Lớp tối phủ lên nền cho nội dung dễ đọc & nền không "đè" như giao diện thứ 2
                        Color.black.opacity(0.55).ignoresSafeArea().allowsHitTesting(false)
                    }
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
            .sheet(isPresented: $showContacts) {
                if let c = contacts { StoreContactsSheet(contacts: c) }
            }
            .task {
                // Chỉ tải 1 lần khi mở cửa hàng. KHÔNG tự poll 30s nữa —
                // việc gán lại dữ liệu theo chu kỳ làm lưới sản phẩm vẽ lại,
                // ảnh nạp lại → giao diện bị "giật". Muốn cập nhật: vuốt để làm mới.
                await reload()
            }
            .refreshable { await reload() }
            .onReceive(flashTimer) { t in
                if let c = config, (c.flashEnabled ?? false), (c.flashEnd ?? 0) > Int(Date().timeIntervalSince1970) {
                    flashNow = t
                }
            }
            .onReceive(showcaseTimer) { _ in showcaseTick += 1 }
        }
    }

    private var appearanceMenu: some View { AppearanceMenu() }

    // ======================== Mặt tiền cửa hàng (theo mẫu) ========================
    // Sản phẩm đang flash sale (nếu admin bật + còn thời gian)
    private var flashProduct: StoreProduct? {
        guard let c = config, (c.flashEnabled ?? false),
              let pid = c.flashProductId, pid > 0,
              (c.flashEnd ?? 0) > Int(Date().timeIntervalSince1970) else { return nil }
        return allProducts.first { $0.id == pid }
    }

    // 4 thẻ tin cậy (2×2)
    private var trustBadgesSection: some View {
        let items: [(String, String, String, Color)] = [
            ("bolt.fill", store.t("Kích hoạt tức thì", "Instant activation"), store.t("Nhận key ngay sau khi thanh toán", "Get key right after payment"), .yellow),
            ("checkmark.shield.fill", store.t("Bảo hành trọn đời", "Lifetime warranty"), store.t("Hỗ trợ đổi key miễn phí", "Free key replacement"), .purple),
            ("headphones", store.t("Hỗ trợ 24/7", "24/7 support"), store.t("Luôn sẵn sàng giúp bạn", "Always ready to help"), .blue),
            ("lock.fill", store.t("An toàn & Bảo mật", "Safe & Secure"), store.t("Mã hoá thông tin tuyệt đối", "Fully encrypted data"), .green),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.1) { ic, title, sub, color in
                HStack(spacing: 10) {
                    Image(systemName: ic).font(.title3.bold()).foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption.bold()).lineLimit(1)
                        Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // 3 bước: dùng config từ server nếu có, fallback về mặc định
    // 3 ô thống kê: Người dùng · Đã bán · Đánh giá. Số hiển thị = số ẢO (admin đặt) + số THẬT.
    private var statsSection: some View {
        let users   = (config?.statUsersBase ?? 0)   + (config?.statUsersReal ?? 0)
        let sold    = (config?.statSoldBase ?? 0)    + (config?.statSoldReal ?? 0)
        let reviews = (config?.statReviewsBase ?? 0) + (config?.statReviewsReal ?? 0)
        let items: [(String, Int, String, Color)] = [
            ("person.2.fill",  users,   store.t("Người dùng", "Users"),   Theme.accent),
            ("bag.fill",       sold,    store.t("Đã bán", "Sold"),        .green),
            ("star.fill",      reviews, store.t("Đánh giá", "Reviews"),   .orange),
        ]
        return HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                VStack(spacing: 6) {
                    Image(systemName: s.0).font(.title3)
                        .frame(width: 46, height: 46)
                        .background(s.3.opacity(0.15)).foregroundStyle(s.3)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(kGroupNumber(s.1)).font(.headline.bold().monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(s.2).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // Flash sale + đếm ngược
    private func flashSection(_ p: StoreProduct) -> some View {
        let end = config?.flashEnd ?? 0
        let remain = max(0, end - Int(flashNow.timeIntervalSince1970))
        let d = remain / 86400, h = (remain % 86400) / 3600, m = (remain % 3600) / 60, s = remain % 60
        let disc = config?.flashDiscount ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(config?.flashTitle ?? "FLASH SALE", systemImage: "bolt.fill")
                    .font(.headline).foregroundStyle(.orange)
                Spacer()
                HStack(spacing: 4) {
                    ForEach([("\(d)", store.t("Ngày","D")), ("\(h)", store.t("Giờ","H")), ("\(m)", store.t("Phút","M")), ("\(s)", store.t("Giây","S"))], id: \.1) { val, unit in
                        VStack(spacing: 1) {
                            Text(val).font(.caption.bold().monospacedDigit())
                                .frame(minWidth: 26).padding(.vertical, 3)
                                .background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(unit).font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink { StoreProductDetailView(productId: p.id) } label: {
                HStack(spacing: 12) {
                    StoreThumb(media: p.media, height: 80).frame(width: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.name).font(.subheadline.bold()).lineLimit(2).foregroundStyle(.primary)
                        if let pr = p.prices.first {
                            HStack(spacing: 6) {
                                if disc > 0 {
                                    Text(kFormatVND(pr.amount * (100 - disc) / 100)).font(.subheadline.bold()).foregroundStyle(.orange)
                                    Text(kFormatVND(pr.amount)).font(.caption).strikethrough().foregroundStyle(.secondary)
                                    Text("-\(disc)%").font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.red).foregroundStyle(.white).clipShape(Capsule())
                                } else {
                                    Text(kFormatVND(pr.amount)).font(.subheadline.bold()).foregroundStyle(.orange)
                                }
                            }
                        }
                        stockMini(p.availableKeys)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(LinearGradient(colors: [Color.orange.opacity(0.12), Color(.secondarySystemBackground)], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func stockMini(_ n: Int) -> some View {
        let label = n == 0 ? store.t("Hết hàng","Sold out") : store.t("Còn","Left") + " \(n)"
        Text(label).font(.caption2.bold())
            .foregroundStyle(n == 0 ? .red : .green)
    }

    // Bảng xếp hạng nạp tích luỹ (top 5)
    private func leaderboardSection(_ leaders: [ShowcaseLeader]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("Bảng xếp hạng nạp tích luỹ", "Top-up leaderboard"), systemImage: "crown.fill")
                .font(.headline).foregroundStyle(Theme.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(leaders) { l in
                        VStack(spacing: 6) {
                            Text("\(l.rank)").font(.headline.bold()).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(rankColor(l.rank)).clipShape(Circle())
                            Text(l.user).font(.caption2).lineLimit(1)
                            Text(kFormatVND(l.total)).font(.caption.bold().monospacedDigit()).foregroundStyle(.green)
                        }
                        .frame(width: 96).padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
    private func rankColor(_ r: Int) -> Color {
        switch r { case 1: return .orange; case 2: return .gray; case 3: return .brown; default: return Theme.accent }
    }

    // Giao dịch gần đây (realtime) — dải tự cuộn nằm trong AutoScrollTicker
    private func transactionsSection(_ orders: [ShowcaseOrder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("Giao dịch gần đây", "Recent purchases"), systemImage: "bag.fill").font(.headline)
                Spacer(); realtimeBadge
            }
            AutoScrollTicker(items: orders) { o in
                HStack(spacing: 10) {
                    Text(String(o.user.prefix(1)).uppercased()).font(.caption.bold())
                        .frame(width: 30, height: 30).background(Theme.accent.opacity(0.15))
                        .foregroundStyle(Theme.accent).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(o.user).bold() + Text(" " + store.t("mua","bought") + " ") + Text(o.product).bold())
                            .font(.caption).lineLimit(1)
                        Text((o.label.isEmpty ? "" : o.label + " · ") + timeAgo(o.at))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(kFormatVND(o.amount)).font(.caption.bold()).foregroundStyle(.primary)
                }
            }
        }
    }

    // Nạp tiền gần đây (realtime) — tự cuộn lên 5 giây/lần
    private func topupsSection(_ topups: [ShowcaseTopup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("Nạp tiền gần đây", "Recent top-ups"), systemImage: "wallet.pass.fill").font(.headline)
                Spacer(); realtimeBadge
            }
            AutoScrollTicker(items: topups) { t in
                HStack(spacing: 10) {
                    Text(String(t.user.prefix(1)).uppercased()).font(.caption.bold())
                        .frame(width: 30, height: 30).background(Color.green.opacity(0.15))
                        .foregroundStyle(.green).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(t.user).bold() + Text(" " + store.t("đã nạp","topped up")))
                            .font(.caption).lineLimit(1)
                        Text(timeAgo(t.at)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text("+" + kFormatVND(t.amount)).font(.caption.bold()).foregroundStyle(.green)
                }
            }
        }
    }

    private var realtimeBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("REALTIME").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
    }

    private func timeAgo(_ at: Int) -> String {
        let s = max(0, Int(Date().timeIntervalSince1970) - at)
        if s < 60 { return store.t("vừa xong", "just now") }
        if s < 3600 { return "\(s/60) " + store.t("phút trước", "min ago") }
        if s < 86400 { return "\(s/3600) " + store.t("giờ trước", "h ago") }
        return "\(s/86400) " + store.t("ngày trước", "d ago")
    }

    // Thanh ví: bấm để nạp tiền / xem số dư
    private var walletBar: some View {
        VStack(spacing: 10) {
            Button { showWallet = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 44, height: 44)
                        Image(systemName: "wallet.pass.fill").font(.title3.bold()).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(store.t("Ví cửa hàng", "Store wallet"))
                                .font(.subheadline.bold()).foregroundStyle(.white)
                            if let pct = config?.topupBonusPercent, pct > 0 {
                                Text("KM +\(pct)%").font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.2)).foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(store.t("Nhấn để nạp tiền & xem số dư", "Tap to top up & view balance"))
                            .font(.caption2).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold()).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.75), Color.purple.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            if let promoUrl = config?.promoImageUrl, !promoUrl.isEmpty, let url = URL(string: promoUrl) {
                if let pid = config?.promoProductId, pid > 0 {
                    NavigationLink { StoreProductDetailView(productId: pid) } label: {
                        promoImageView(url: url, raw: promoUrl)
                            .frame(maxHeight: 80).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                } else {
                    promoImageView(url: url, raw: promoUrl)
                        .frame(maxHeight: 80).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder private func promoImageView(url: URL, raw: String) -> some View {
        if isAnimatedImage(raw) {
            GIFWebView(url: url, contentMode: "cover")
        } else {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color(.secondarySystemBackground)
            }
        }
    }

    private func sectionHeader(title: String, icon: String, color: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline.bold()).foregroundStyle(color)
            Text(title).font(.headline.bold())
        }
    }

    // Mục "Tải về" hiện ngay khi vào cửa hàng (bản tải miễn phí)
    // Sản phẩm có file/link tải (hasDownload = true) — hiển thị cùng khu vực Tải về.
    // Loại các sản phẩm đã có trong feed /store/downloads để không hiện trùng;
    // phần này chỉ là dự phòng khi feed tải lỗi (mạng chậm) mà danh mục đã có.
    private var downloadableProducts: [StoreProduct] {
        let dlIds = Set(downloads.map { $0.id })
        return allProducts.filter { $0.hasDownload && !dlIds.contains($0.id) }
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: store.t("Tải về", "Downloads"), icon: "arrow.down.circle.fill", color: .blue)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(downloads) { d in downloadCard(d) }
                    ForEach(downloadableProducts) { p in productDownloadCard(p) }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func downloadCard(_ d: StoreDownloadItem) -> some View {
        let url = !d.downloadUrl.isEmpty ? URL(string: d.downloadUrl) : store.api.storeDownloadURL(productId: d.id)
        let filename: String? = {
            guard let u = url else { return nil }
            let lc = (u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent)
            return lc.contains(".") && lc.count > 3 ? lc : nil
        }()
        return VStack(alignment: .leading, spacing: 0) {
            StoreThumb(media: d.media, height: 90)
            VStack(alignment: .leading, spacing: 5) {
                Text(d.name).font(.caption.bold()).lineLimit(2)
                if let url {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(store.t("Tải", "Download") + " " + d.name)
                                    .font(.caption2.bold()).lineLimit(1)
                                if let fn = filename {
                                    Text(fn).font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 4)
                        .background(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 160)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // Thẻ tải xuống cho sản phẩm có link/file (hasDownload = true)
    private func productDownloadCard(_ p: StoreProduct) -> some View {
        let url = store.api.storeDownloadURL(productId: p.id)
        return NavigationLink {
            StoreProductDetailView(productId: p.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                StoreThumb(media: p.media, height: 90)
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.name).font(.caption.bold()).lineLimit(2).foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(store.t("Tải", "Download") + " " + p.name)
                            .font(.caption2.bold()).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 4)
                    .background(LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    if let url {
                        Link(destination: url) {
                            Text(store.t("Link trực tiếp", "Direct link"))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 160)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // Toàn bộ sản phẩm — hiện ngay khi vào cửa hàng
    private var allProductsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: store.t("Tất cả sản phẩm", "All products"), icon: "bag.fill", color: Theme.accent)
                Spacer()
                Menu {
                    Picker(store.t("Sắp xếp", "Sort"), selection: $productSort) {
                        Text(store.t("Mặc định", "Default")).tag("default")
                        Text(store.t("Giá tăng dần", "Price: Low → High")).tag("priceAsc")
                        Text(store.t("Giá giảm dần", "Price: High → Low")).tag("priceDesc")
                        Text(store.t("Tên A-Z", "Name A-Z")).tag("name")
                    }
                    Divider()
                    Picker(store.t("Lọc", "Filter"), selection: $productFilter) {
                        Text(store.t("Tất cả", "All")).tag("all")
                        Text(store.t("Còn hàng", "In stock")).tag("inStock")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .padding(8)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(displayProducts.enumerated()), id: \.element.id) { idx, product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product, index: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // Khoảng giá "min ~ max" (như mẫu) — 1 giá thì hiện 1
    private func priceRange(_ p: StoreProduct) -> String {
        guard !p.prices.isEmpty else { return "" }
        let amounts = p.prices.map { $0.amount }
        let lo = amounts.min() ?? 0, hi = amounts.max() ?? 0
        return lo == hi ? kFormatVND(lo) : "\(kFormatVND(lo)) ~ \(kFormatVND(hi))"
    }

    private func allProductCard(_ p: StoreProduct, index: Int = 0) -> some View {
        let inStock = p.availableKeys > 0
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                StoreThumb(media: p.media, height: productThumbHeight)
                // Badge ACTIVE / Hết hàng (góc trái) như mẫu
                HStack(spacing: 3) {
                    Circle().fill(inStock ? Color.green : Color.red).frame(width: 5, height: 5)
                    Text(inStock ? "ACTIVE" : store.t("Hết hàng", "Sold out"))
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(5)
                // Tim yêu thích (góc phải)
                Button { toggleWishlist(p.id) } label: {
                    Image(systemName: wishlistIds.contains(p.id) ? "heart.fill" : "heart")
                        .font(.caption2.bold())
                        .foregroundStyle(wishlistIds.contains(p.id) ? .red : .white)
                        .padding(5).background(.ultraThinMaterial).clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(5)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    // ID THẬT của sản phẩm (khớp với ID trong quản lý sản phẩm / Flash sale / Khuyến mãi)
                    Text(String(format: "#%02d", p.id))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                    Text(p.name)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !p.prices.isEmpty {
                    Text(priceRange(p))
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                // Lượt xem (mắt) + số key/acc còn lại
                HStack(spacing: 8) {
                    Label("\(kGroupNumber(p.views ?? 0))", systemImage: "eye.fill")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Label("\(p.availableKeys)", systemImage: "key.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(p.availableKeys > 0 ? .green : .red)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 10))
                    Text(store.t("Mua ngay", "Buy now"))
                        .font(.caption2.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    inStock
                    ? LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)],
                                     startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(7)
        }
        .frame(width: productCardWidth)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.09), radius: 5, x: 0, y: 3)
    }

    // "Danh mục Game": gom sản phẩm theo từng danh mục thành lưới 2 cột (như mẫu)
    private var gameCatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("Danh mục Game", "Game categories"), systemImage: "gamecontroller.fill").font(.headline)
            ForEach(filteredCategories) { cat in
                if let prods = productsByCategory[cat.id], !prods.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            if let m = cat.media.first, m.type != "video", let url = URL(string: m.url) {
                                Group {
                                    if isAnimatedImage(m.url) {
                                        GIFWebView(url: url)
                                    } else {
                                        CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                        placeholder: { Color(.tertiarySystemBackground) }
                                    }
                                }
                                    .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "folder.fill").foregroundStyle(Theme.gold)
                                    .frame(width: 38, height: 38)
                                    .background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cat.name).font(.subheadline.bold()).lineLimit(1)
                                Text("\(prods.count) " + store.t("sản phẩm", "products"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            NavigationLink { StoreFolderListView(category: cat) } label: {
                                HStack(spacing: 2) {
                                    Text(store.t("Xem thêm", "See all")).font(.caption.bold())
                                    Image(systemName: "chevron.right").font(.caption2)
                                }.foregroundStyle(Theme.accent)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(prods.prefix(max(1, config?.gamecatLimit ?? 6))) { p in
                                NavigationLink { StoreProductDetailView(productId: p.id) } label: {
                                    productGridCard(p)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // Thẻ sản phẩm co giãn cho lưới 2 cột (badge ACTIVE + khoảng giá + Mua ngay)
    private func productGridCard(_ p: StoreProduct) -> some View {
        let inStock = p.availableKeys > 0
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                StoreThumb(media: p.media, height: 96)
                HStack(spacing: 3) {
                    Circle().fill(inStock ? Color.green : Color.red).frame(width: 5, height: 5)
                    Text(inStock ? "ACTIVE" : store.t("Hết hàng", "Sold out"))
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.ultraThinMaterial).clipShape(Capsule()).padding(5)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(p.name).font(.caption.bold()).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !p.prices.isEmpty {
                    Text(priceRange(p)).font(.caption2.bold()).foregroundStyle(Theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill").font(.system(size: 10))
                    Text(store.t("Mua ngay", "Buy now")).font(.caption2.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(inStock ? Theme.accent : Color.gray).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Màu cho thanh thông báo theo tên cấu hình
    private func announceColor(_ name: String?) -> Color {
        switch name {
        case "red": return .red
        case "green": return .green
        case "gold": return Theme.gold
        case "purple": return Theme.purple
        default: return Theme.accent
        }
    }

    // Thanh thông báo chạy đầu trang (loa + chữ cuộn ngang)
    private func announceBar(_ text: String) -> some View {
        let color = announceColor(config?.announceColor)
        return HStack(spacing: 8) {
            Image(systemName: "megaphone.fill").font(.caption).foregroundStyle(color)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.caption.bold()).foregroundStyle(.primary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // (Hero đã được gộp thẳng vào storeHeader — không còn khối riêng.)

    // Footer cuối trang: logo + slogan
    private var footerSection: some View {
        let sloganText: String = {
            let s = (config?.slogan ?? "").trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? store.t("Cửa hàng sản phẩm số · key · tải về", "Digital store · keys · downloads") : s
        }()
        let sloganEff = config?.sloganEffect ?? "none"
        let sloganAnim = config?.sloganAnim ?? "none"
        return VStack(spacing: 8) {
            AnimatedStoreLogo(
                text: displayName,
                effect: effectiveConfig?.logoEffect ?? "rainbow",
                fontStyle: effectiveConfig?.logoFont ?? "rounded",
                anim: effectiveConfig?.logoAnim ?? "shimmer",
                size: 22)
            if sloganEff != "none" {
                AnimatedStoreText(
                    text: sloganText,
                    effect: sloganEff,
                    font: keniosFont(config?.sloganFont ?? "rounded", size: 12),
                    anim: sloganAnim)
                    .multilineTextAlignment(.center)
            } else {
                Text(sloganText)
                    .font(keniosFont(config?.sloganFont ?? "rounded", size: 12))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("© " + String(Calendar.current.component(.year, from: Date())) + " " + displayName)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: store.t("Yêu thích", "Wishlist"), icon: "heart.fill", color: .red)
                Spacer()
                Text("\(wishlistProducts.count) " + store.t("sản phẩm", "products"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(wishlistProducts.enumerated()), id: \.element.id) { idx, product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product, index: idx)
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
            sectionHeader(title: store.t("Đã xem gần đây", "Recently viewed"), icon: "clock.arrow.circlepath")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(recentProducts.enumerated()), id: \.element.id) { idx, product in
                        NavigationLink { StoreProductDetailView(productId: product.id) } label: {
                            allProductCard(product, index: idx)
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

    // Icon liên hệ nhanh: hiện tối đa 3 icon preview + badge số còn lại, bấm mở sheet danh sách
    @ViewBuilder private var headerContactIcons: some View {
        let enabled = (contacts?.contact ?? []).filter {
            $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let hasGroups = (contacts?.groups ?? []).contains {
            $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !enabled.isEmpty || hasGroups {
            // 1 nút duy nhất → bấm vào mở bảng liên hệ (admin & nhóm cộng đồng)
            Button { showContacts = true } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = effectiveConfig, !c.bannerUrl.isEmpty {
                // ===== Banner-Hero: tiêu đề + dòng phụ + nút "Mua ngay" ĐÈ LÊN ảnh banner (1 khối) =====
                StoreMediaCarousel(
                    media: [StoreMedia(type: c.bannerType, url: c.bannerUrl)], height: 235,
                    videoFit: true)   // video hero hiện ĐỦ khung, không bị cắt; kích thước hero giữ nguyên
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.35), .clear, .black.opacity(0.78)],
                            startPoint: .top, endPoint: .bottom)
                    }
                    // Logo + slogan ở góc trên-trái (chữ trắng cho nổi trên ảnh)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 10) {
                            StoreLogoPlayer(urlString: c.logoUrl, mediaType: c.logoType, size: 48)
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.25), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                AnimatedStoreLogo(
                                    text: displayName,
                                    effect: c.logoEffect ?? "rainbow",
                                    fontStyle: c.logoFont ?? "rounded",
                                    anim: c.logoAnim ?? "shimmer",
                                    size: 20)
                                Text({
                                    let s = (config?.slogan ?? "").trimmingCharacters(in: .whitespaces)
                                    return s.isEmpty ? store.t("Cửa hàng sản phẩm số · key · tải về", "Digital store · keys · downloads") : s
                                }())
                                .font(keniosFont(config?.sloganFont ?? "rounded", size: 12))
                                .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 14).padding(.top, 14)
                        .padding(.trailing, 56)   // chừa chỗ cho icon chat góc phải
                    }
                    .overlay(alignment: .topTrailing) {
                        headerContactIcons.padding(12)
                    }
                    .overlay(alignment: .bottomLeading) {
                        heroBlock(onImage: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(alignment: .top, spacing: 12) {
                    StoreLogoPlayer(urlString: effectiveConfig?.logoUrl ?? "", mediaType: effectiveConfig?.logoType, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        AnimatedStoreLogo(
                            text: displayName,
                            effect: effectiveConfig?.logoEffect ?? "rainbow",
                            fontStyle: effectiveConfig?.logoFont ?? "rounded",
                            anim: effectiveConfig?.logoAnim ?? "shimmer",
                            size: 22)
                        let sloganText: String = {
                            let s = (config?.slogan ?? "").trimmingCharacters(in: .whitespaces)
                            return s.isEmpty ? store.t("Cửa hàng sản phẩm số · key · tải về", "Digital store · keys · downloads") : s
                        }()
                        if let eff = config?.sloganEffect, eff != "none" {
                            AnimatedStoreText(
                                text: sloganText,
                                effect: eff,
                                font: keniosFont(config?.sloganFont ?? "rounded", size: 12),
                                anim: config?.sloganAnim ?? "none")
                        } else {
                            Text(sloganText)
                                .font(keniosFont(config?.sloganFont ?? "rounded", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    headerContactIcons
                }
                .padding(.vertical, 8)
                // Không có banner thì hiện hero trên nền thường, ngay dưới hàng logo.
                heroBlock(onImage: false)
            }
        }
    }

    // Khối hero: tiêu đề lớn + dòng phụ + nút "Mua ngay".
    // onImage=true → nằm ĐÈ lên ảnh banner (dòng phụ chữ trắng, nút nền trắng cho nổi).
    @ViewBuilder
    private func heroBlock(onImage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let heroTitle: String = {
                let t = (config?.heroTitle ?? "").trimmingCharacters(in: .whitespaces)
                return t.isEmpty
                    ? store.t("GAME CHẤT LƯỢNG CAO · GIÁ TỐT NHẤT", "TOP QUALITY · BEST PRICE")
                    : t
            }()
            AnimatedStoreText(
                text: heroTitle,
                effect: config?.heroEffect ?? "gradient",
                font: keniosFont(config?.heroFont ?? "rounded-bold", size: 20),
                anim: config?.heroAnim ?? "none")
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(3)
            Text({
                let s = (config?.heroSubtitle ?? "").trimmingCharacters(in: .whitespaces)
                return s.isEmpty
                    ? store.t("Uy tín · Giao key tức thì · Bảo hành trọn đời", "Trusted · Instant key · Lifetime warranty")
                    : s
            }())
            .font(.subheadline)
            .foregroundStyle(onImage ? Color.white.opacity(0.92) : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                // Luôn cuộn tới mục "Tất cả sản phẩm"; nếu admin ẩn thì rơi về "gamecat".
                scrollTarget = orderedSections.contains("products") ? "products" : "gamecat"
            } label: {
                HStack(spacing: 6) {
                    Text(store.t("Mua ngay", "Shop now")).font(.headline.bold())
                    Image(systemName: "arrow.right")
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(onImage ? Color.white : Theme.accent)
                .foregroundStyle(onImage ? Theme.accent : Color.white)
                .clipShape(Capsule())
            }
        }
    }

    private func categoryCard(_ cat: StoreCategory) -> some View {
        ZStack(alignment: .bottomLeading) {
            StoreThumb(media: cat.media, height: categoryThumbHeight)
            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top, endPoint: .bottom)
            Text(cat.name)
                .font(cardScale < 0.85 ? .caption.bold() : .subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 3)
    }

    private func reload() async {
        loading = true; error = nil
        // KHÔNG xoá toàn bộ cache ảnh ở đây: làm vậy khiến mọi AsyncImage nạp lại,
        // ảnh thu về placeholder → bố cục co lại → trang bị "nhảy" khi kéo tải lại.
        async let cfgTask = store.api.storeConfig()
        async let dlTask  = store.api.storeDownloads()
        async let ctTask  = store.api.storeContacts()
        async let catTask = store.api.storeCategories()
        async let showTask = store.api.storeShowcase()
        // CHỈ gán khi dữ liệu THỰC SỰ đổi → tránh vẽ lại / nhấp nháy mỗi lần poll 30s.
        if let s = try? await showTask, s != showcase { showcase = s }
        if let c = try? await cfgTask {
            if c != config { config = c }
            // lưu cache để lần sau (kể cả khi offline) vẫn giữ tên/logo/banner + thứ tự bố cục
            cfgName = c.logoName; cfgLogo = c.logoUrl; cfgLogoType = c.logoType ?? "image"
            cfgBannerType = c.bannerType; cfgBannerUrl = c.bannerUrl
            cfgSectionOrder = c.sectionOrder ?? ""
            cfgSectionHidden = c.sectionHidden ?? ""
        }
        // CHỈ cập nhật khi tải downloads THÀNH CÔNG. Nếu lỗi tạm thời (mạng chập chờn lúc
        // kéo tải lại) thì GIỮ nguyên danh sách cũ — tránh mục "Tải về" biến mất rồi hiện
        // lại khiến cả trang nhảy sang bố cục khác.
        if let dl = try? await dlTask, dl != downloads { downloads = dl }
        if let ct = try? await ctTask, ct != contacts { contacts = ct }
        if let cats = try? await catTask {
            if cats != categories { categories = cats }
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

        // Nhanh: lấy hết sản phẩm trong 1 request (gom theo danh mục). Lỗi/backend cũ → quay về cách cũ.
        if let groupedFast = try? await store.api.storeAllProducts(), !groupedFast.isEmpty {
            var seenFast = Set<Int>()
            var flat: [StoreProduct] = []
            let extraIds = groupedFast.keys.filter { id in !categories.contains { $0.id == id } }
            for cid in categories.map({ $0.id }) + extraIds {
                for p in (groupedFast[cid] ?? []) where !seenFast.contains(p.id) {
                    seenFast.insert(p.id); flat.append(p)
                }
            }
            if productsByCategory != groupedFast { productsByCategory = groupedFast }
            if allProducts != flat { allProducts = flat }
            loadingProducts = false
            return
        }

        var seen = Set<Int>()
        var products: [StoreProduct] = []
        var grouped: [Int: [StoreProduct]] = [:]
        await withTaskGroup(of: (Int, [StoreProduct]).self) { group in
            for cat in categories {
                group.addTask {
                    let folders = (try? await self.store.api.storeFolders(categoryId: cat.id)) ?? []
                    var catProducts: [StoreProduct] = []
                    for folder in folders {
                        let prods = (try? await self.store.api.storeProducts(folderId: folder.id)) ?? []
                        catProducts.append(contentsOf: prods)
                    }
                    return (cat.id, catProducts)
                }
            }
            for await (catId, batch) in group {
                grouped[catId] = batch
                for p in batch where !seen.contains(p.id) {
                    seen.insert(p.id)
                    products.append(p)
                }
            }
        }
        if allProducts != products { allProducts = products }
        if productsByCategory != grouped { productsByCategory = grouped }
        loadingProducts = false
    }
}

