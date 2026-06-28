import SwiftUI
import AVKit

// ============================ Tiện ích chung ============================
func kFormatVND(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return (f.string(from: NSNumber(value: amount)) ?? "\(amount)") + "đ"
}

// Carousel ảnh/video (link) — tối đa 5
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
            }
            .frame(height: height)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
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
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(.tertiarySystemBackground)
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
    @State private var downloads: [StoreDownloadItem] = []
    @State private var contacts: StoreContacts?
    @State private var search = ""

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
            .navigationTitle(config?.logoName ?? "Ứng dụng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMyOrders = true } label: {
                        Image(systemName: "bag.badge.questionmark")
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
            .sheet(isPresented: $showAdmin) { StoreAdminView() }
            .sheet(isPresented: $showMyOrders) { StoreMyOrdersView() }
            .sheet(isPresented: $showWallet) { StoreWalletView() }
            .task { await reload() }
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
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color(.secondarySystemBackground) }
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
        config = try? await store.api.storeConfig()
        downloads = (try? await store.api.storeDownloads()) ?? []
        contacts = try? await store.api.storeContacts()
        do { categories = try await store.api.storeCategories() }
        catch { self.error = error.localizedDescription }
        loading = false
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
                    Text(p.name).font(.title2.bold())
                    if !p.description.isEmpty {
                        Text(p.description).font(.subheadline).foregroundStyle(.secondary)
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
        .task { await reload() }
        .sheet(isPresented: $showWallet, onDismiss: { Task { await reloadBalance() } }) {
            StoreWalletView()
        }
    }

    // Đã mua: hiện key + nút tải game
    @ViewBuilder private func ownedSection(_ m: StoreProductMine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bạn đã sở hữu sản phẩm này", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if let msg = m.delivery, !msg.isEmpty {
                // Tin nhắn giao hàng đầy đủ: sản phẩm + nền tảng + thời hạn + ngày hết hạn + key
                VStack(alignment: .leading, spacing: 8) {
                    Text(msg).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { UIPasteboard.general.string = msg } label: {
                        Label("Sao chép", systemImage: "doc.on.doc").font(.caption.bold())
                    }
                }
                .padding(12).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let key = m.key, !key.isEmpty {
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
                                    downloadUrl: r.downloadUrl, downloadFileId: r.downloadFileId,
                                    delivery: r.delivery, expiresAt: r.expiresAt)
            info = r.delivery ?? r.message
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
            if let msg = o.delivery, !msg.isEmpty {
                HStack(alignment: .top) {
                    Text(msg).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { UIPasteboard.general.string = msg } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let key = o.key, !key.isEmpty {
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
