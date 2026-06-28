import SwiftUI
import AVKit
import WebKit

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
            Group {
                if isAnimatedImage(m.url) {
                    GIFWebView(url: url)
                } else {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color(.tertiarySystemBackground) }
                }
            }
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
        // Gửi lên server để cộng vào "lượt đánh giá" (mỗi khách 1 đánh giá/sản phẩm)
        Task { try? await store.api.storeReview(productId: productId, stars: stars) }
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

                    // Lượt xem (mắt) + số key/acc còn lại
                    HStack(spacing: 14) {
                        Label("\(kGroupNumber(p.views ?? 0)) " + store.t("lượt xem", "views"), systemImage: "eye.fill")
                            .font(.caption).foregroundStyle(.secondary)
                        Label(p.availableKeys > 0
                              ? "\(store.t("Còn", "Left")) \(p.availableKeys) \(p.stockLabel)"
                              : store.t("Hết hàng", "Out of stock"), systemImage: "key.fill")
                            .font(.caption.bold())
                            .foregroundStyle(p.availableKeys > 0 ? .green : .red)
                    }

                    // Đã sở hữu thì vẫn hiện key cũ + cho phép MUA THÊM lần nữa (không giới hạn lượt mua)
                    if let m = mine, m.owned {
                        ownedSection(m)
                    }
                    buySection(p)
                    if let m = mine, m.owned {
                        ratingSection
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
        .task {
            // Mỗi lần mở sản phẩm = +1 lượt xem (không giới hạn), rồi tải lại để hiện số mới
            try? await store.api.storeProductView(productId: productId)
            await reload()
            trackRecentView(productId)
        }
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
            if let msg = m.delivery, !msg.isEmpty {
                // Tin nhắn giao hàng đầy đủ: sản phẩm + nền tảng + thời hạn + ngày hết hạn + key
                VStack(alignment: .leading, spacing: 8) {
                    Text(msg).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { UIPasteboard.general.string = msg } label: {
                        Label(store.t("Sao chép", "Copy"), systemImage: "doc.on.doc").font(.caption.bold())
                    }
                }
                .padding(12).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let key = m.key, !key.isEmpty {
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

