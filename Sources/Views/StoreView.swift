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

// ============================ App bán hàng (khách) ============================
struct StoreView: View {
    @EnvironmentObject var store: AppStore

    @State private var config: StoreAppConfig?
    @State private var categories: [StoreCategory] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdmin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storeHeader

                    if loading && categories.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                    } else if categories.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bag").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Chưa có danh mục sản phẩm nào.")
                                .foregroundStyle(.secondary)
                            if store.isAdmin {
                                Text("Bấm biểu tượng ⚙️ ở góc trên để thêm danh mục, sản phẩm.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(categories) { cat in
                            NavigationLink {
                                StoreFolderListView(category: cat)
                            } label: {
                                categoryCard(cat)
                            }
                            .buttonStyle(.plain)
                        }
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
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private var appearanceMenu: some View { AppearanceMenu() }

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
            StoreMediaCarousel(media: cat.media, height: 150)
            HStack {
                Text(cat.name).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reload() async {
        loading = true; error = nil
        config = try? await store.api.storeConfig()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading && products.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if products.isEmpty {
                    Text("Chưa có sản phẩm nào.").foregroundStyle(.secondary)
                } else {
                    ForEach(products) { p in
                        NavigationLink {
                            StoreProductDetailView(productId: p.id)
                        } label: { productRow(p) }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func productRow(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StoreMediaCarousel(media: p.media, height: 160)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.headline)
                if let cheapest = p.prices.map(\.amount).min() {
                    Text("Từ \(kFormatVND(cheapest))").font(.subheadline).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 8) {
                    Text(p.availableKeys > 0 ? "Còn \(p.availableKeys) key" : "Tạm hết key")
                        .font(.caption2)
                        .foregroundStyle(p.availableKeys > 0 ? .green : .red)
                    if p.hasDownload {
                        Label("Có bản tải", systemImage: "arrow.down.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
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
    @State private var order: StoreOrderCreateResponse?
    @State private var loading = false
    @State private var buying = false
    @State private var checking = false
    @State private var error: String?
    @State private var info: String?

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
    }

    // Đã mua: hiện key + nút tải game
    @ViewBuilder private func ownedSection(_ m: StoreProductMine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bạn đã sở hữu sản phẩm này", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if let key = m.key, !key.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KEY của bạn").font(.caption).foregroundStyle(.secondary)
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
        } else {
            Text("Sản phẩm chưa có bản tải. Liên hệ admin.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // Chưa mua: chọn gói thời hạn → tạo đơn → QR → kiểm tra
    @ViewBuilder private func buySection(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if p.prices.isEmpty {
                Text("Sản phẩm chưa có giá bán.").foregroundStyle(.secondary)
            } else {
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

                if order == nil {
                    Button {
                        Task { await createOrder(p) }
                    } label: {
                        HStack {
                            if buying { ProgressView().tint(.white) }
                            Text(buying ? "Đang tạo đơn..." : "Mua ngay")
                        }
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(p.availableKeys > 0 ? Theme.purple : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(buying || p.availableKeys <= 0 || (selectedPrice == nil && p.prices.count > 1))
                }
            }

            if let o = order { paymentBox(o) }
        }
    }

    @ViewBuilder private func paymentBox(_ o: StoreOrderCreateResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quét mã QR để chuyển khoản").font(.headline)
            if let qr = o.qrUrl, let url = URL(string: qr) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit().frame(maxWidth: 260).frame(maxWidth: .infinity)
                } placeholder: { ProgressView().frame(maxWidth: .infinity) }
            }
            LabeledContent("Ngân hàng", value: o.bankInfo.bank)
            LabeledContent("Số tài khoản", value: o.bankInfo.account)
            LabeledContent("Chủ tài khoản", value: o.bankInfo.name)
            LabeledContent("Nội dung CK", value: o.bankInfo.content)
            LabeledContent("Số tiền", value: kFormatVND(o.amount))
            Text(o.message).font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await checkPaid() }
            } label: {
                HStack {
                    if checking { ProgressView() }
                    Text(checking ? "Đang kiểm tra..." : "Tôi đã chuyển khoản — kiểm tra")
                }
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Color.green.opacity(0.18)).foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(checking)
            Text("Hệ thống tự xác nhận trong ~20 giây sau khi nhận tiền. Nếu chưa thấy key, đợi chút rồi bấm kiểm tra lại.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding().background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reload() async {
        loading = true; error = nil
        do {
            let p = try await store.api.storeProduct(productId)
            product = p
            if selectedPrice == nil { selectedPrice = p.prices.first }
        } catch { self.error = error.localizedDescription }
        mine = try? await store.api.storeProductMine(productId)
        loading = false
    }

    private func createOrder(_ p: StoreProduct) async {
        buying = true; error = nil; info = nil
        do {
            order = try await store.api.storeCreateOrder(productId: p.id,
                                                         priceId: selectedPrice?.id)
        } catch { self.error = error.localizedDescription }
        buying = false
    }

    private func checkPaid() async {
        checking = true; error = nil
        let m = try? await store.api.storeProductMine(productId)
        if let m, m.owned {
            mine = m; order = nil
            info = "Thanh toán thành công! Key đã được cấp."
        } else {
            info = "Chưa nhận được thanh toán. Vui lòng đợi thêm rồi kiểm tra lại."
        }
        checking = false
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
