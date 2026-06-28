import SwiftUI
import AVKit
import WebKit

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
