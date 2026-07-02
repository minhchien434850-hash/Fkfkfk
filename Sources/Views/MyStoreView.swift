import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// §7 — Đa người bán: "Cửa hàng của tôi" (tạo store · thêm sản phẩm · chia sẻ Store_ID)
// và "Tìm cửa hàng" theo Store_ID để xem shop người khác. Dữ liệu cô lập, RBAC ở backend.
struct MyStoreView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var seg = 0

    // Cửa hàng của tôi
    @State private var myStore: MyStore?
    @State private var products: [MyStoreProduct] = []
    @State private var categories: [MyStoreCategory] = []
    @State private var newCatName = ""
    @State private var loading = false
    @State private var name = ""
    @State private var desc = ""
    @State private var slogan = ""
    @State private var logoUrl = ""
    @State private var bannerUrl = ""
    // §7 Đợt C — Hiệu ứng chữ (tên/slogan) giống cửa hàng admin
    @State private var nameEffect = "gradient"
    @State private var sloganEffect = "none"
    @State private var nameColor = ""     // "#RRGGBB" khi effect == "solid"
    @State private var sloganColor = ""
    @State private var saving = false
    @State private var message: String?
    @State private var errorMessage: String?

    // Đợt 1 — giao diện: chọn logo / ảnh bìa từ máy
    @State private var logoItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var uploadingLogo = false
    @State private var uploadingBanner = false

    @State private var showAddProduct = false
    @State private var managingProduct: MyStoreProduct?   // Đợt 2B — quản lý giá + KEY
    @State private var stats: MyStoreStats?                // Đợt 3 — thống kê người bán
    @State private var buyTarget: BuyTarget?               // Đợt 3 — mua sản phẩm shop khác

    struct BuyTarget: Identifiable { let id = UUID(); let product: MyStoreProduct; let storeId: Int }

    // Tìm cửa hàng
    @State private var searchId = ""
    @State private var foundStore: MyStore?
    @State private var foundProducts: [MyStoreProduct] = []
    @State private var foundSettings: MyStoreSettings?
    @State private var searchError: String?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                KHeroHeader(icon: "storefront.fill",
                            title: store.t("Cửa hàng của tôi", "My Store"),
                            subtitle: store.t("Mở shop riêng · bán sản phẩm · chia sẻ Store ID",
                                              "Your own shop · sell products · share Store ID"))
                    .padding(.horizontal).padding(.top, 8)

                Picker("", selection: $seg) {
                    Text(store.t("Cửa hàng của tôi", "My Store")).tag(0)
                    Text(store.t("Tìm cửa hàng", "Find a store")).tag(1)
                }
                .pickerStyle(.segmented).padding()

                if seg == 0 { myStorePane } else { findPane }
            }
            .navigationTitle(store.t("Cửa hàng", "Store"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMine() }
            .onChange(of: logoItem) { item in
                guard let item else { return }
                Task { await uploadImage(item, isBanner: false) }
            }
            .onChange(of: bannerItem) { item in
                guard let item else { return }
                Task { await uploadImage(item, isBanner: true) }
            }
            .sheet(isPresented: $showAddProduct) {
                AddMyProductView(categories: categories) { await loadMine() }.environmentObject(store)
            }
            .sheet(item: $managingProduct) { p in
                ManageMyProductView(product: p) { await loadMine() }.environmentObject(store)
            }
            .sheet(item: $buyTarget) { t in
                BuyProductView(product: t.product, storeId: t.storeId).environmentObject(store)
            }
        }
    }

    // MARK: - Cửa hàng của tôi
    @ViewBuilder private var myStorePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading { ProgressView().frame(maxWidth: .infinity) }

                // Xem trước giao diện cửa hàng (ảnh bìa + logo + tên + slogan)
                storefrontPreview

                // Xem MẶT TIỀN đầy đủ như khách nhìn thấy (giống storefront admin)
                if let s = myStore {
                    NavigationLink {
                        VendorStorefrontView(sid: s.id).environmentObject(store)
                    } label: {
                        Label(store.t("Xem cửa hàng của tôi (như khách thấy)", "View my storefront (as customers see)"),
                              systemImage: "eye.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 44)
                            .background(Theme.accent).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Thông tin store (tạo mới hoặc sửa)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("Thông tin cửa hàng", "Store info")).font(.subheadline.bold())
                    TextField(store.t("Tên cửa hàng", "Store name"), text: $name)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                    TextField(store.t("Slogan (dòng giới thiệu ngắn)", "Slogan (short tagline)"), text: $slogan)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                    TextField(store.t("Mô tả (tuỳ chọn)", "Description (optional)"), text: $desc, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))

                    // Chọn logo + ảnh bìa từ máy (tự upload → điền link)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Label(uploadingLogo ? store.t("Đang tải...", "Uploading...")
                                                : (logoUrl.isEmpty ? store.t("Chọn logo", "Pick logo")
                                                                   : store.t("Đổi logo", "Change logo")),
                                  systemImage: "photo.circle").font(.caption.bold())
                        }.disabled(uploadingLogo)
                        Spacer()
                        PhotosPicker(selection: $bannerItem, matching: .images) {
                            Label(uploadingBanner ? store.t("Đang tải...", "Uploading...")
                                                  : (bannerUrl.isEmpty ? store.t("Chọn ảnh bìa", "Pick banner")
                                                                       : store.t("Đổi ảnh bìa", "Change banner")),
                                  systemImage: "photo.badge.plus").font(.caption.bold())
                        }.disabled(uploadingBanner)
                    }
                    .padding(.vertical, 2)

                    Button {
                        Task { await saveStore() }
                    } label: {
                        HStack {
                            if saving { ProgressView().tint(.white) }
                            Text(myStore == nil ? store.t("Tạo cửa hàng", "Create store")
                                                 : store.t("Lưu thay đổi", "Save changes")).bold()
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Theme.accent)
                        .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let message { Text(message).font(.caption).foregroundStyle(.green) }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding().kCard(16)

                // §7 Đợt C — Hiệu ứng chữ tên/slogan (giống cửa hàng admin)
                effectsEditor

                // Store ID + chia sẻ (khi đã có store)
                if let s = myStore {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Store ID").font(.subheadline.bold())
                            Spacer()
                            Text("#\(s.id)").font(.headline.monospaced()).foregroundStyle(Theme.accent)
                        }
                        HStack {
                            Button {
                                UIPasteboard.general.string = "\(s.id)"
                                message = store.t("Đã sao chép Store ID.", "Store ID copied.")
                            } label: {
                                Label(store.t("Sao chép ID", "Copy ID"), systemImage: "doc.on.doc").font(.caption.bold())
                            }.buttonStyle(.bordered)
                            ShareLink(item: store.t("Ghé cửa hàng của tôi trên KENIOS — Store ID: \(s.id)",
                                                    "Visit my store on KENIOS — Store ID: \(s.id)")) {
                                Label(store.t("Chia sẻ", "Share"), systemImage: "square.and.arrow.up").font(.caption.bold())
                            }.buttonStyle(.bordered)
                        }
                    }
                    .padding().kCard(16)

                    // Đợt 3 — Bảng điều khiển: doanh thu + đơn hàng
                    sellerDashboard

                    // Đợt 5 — Cài đặt cửa hàng (thông báo chạy · flash sale · liên hệ)
                    NavigationLink {
                        StoreStorefrontSettingsView(products: products).environmentObject(store)
                    } label: {
                        Label(store.t("Cài đặt cửa hàng (thông báo · flash sale · liên hệ)",
                                      "Storefront settings (announce · flash · contacts)"),
                              systemImage: "slider.horizontal.2.square")
                            .font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Đợt 4 — Ví & Mã giảm giá
                    HStack(spacing: 10) {
                        NavigationLink {
                            SellerWalletView(storeId: s.id).environmentObject(store)
                        } label: {
                            Label(store.t("Ví & Rút tiền", "Wallet"), systemImage: "creditcard")
                                .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        NavigationLink {
                            PromoManagerView().environmentObject(store)
                        } label: {
                            Label(store.t("Mã giảm giá", "Promo codes"), systemImage: "tag")
                                .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Quản lý danh mục (Đợt 2)
                    categoryManager

                    // Sản phẩm — gom theo danh mục
                    HStack {
                        Text(store.t("Sản phẩm (\(products.count))", "Products (\(products.count))")).font(.subheadline.bold())
                        Spacer()
                        Button { showAddProduct = true } label: {
                            Label(store.t("Thêm", "Add"), systemImage: "plus.circle.fill").font(.caption.bold())
                        }
                    }
                    if products.isEmpty {
                        Text(store.t("Chưa có sản phẩm. Bấm \"Thêm\" để đăng bán.",
                                     "No products yet. Tap \"Add\" to sell."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        groupedProducts
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Tìm cửa hàng
    @ViewBuilder private var findPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    MyPurchasesView().environmentObject(store)
                } label: {
                    Label(store.t("Đơn đã mua của tôi", "My purchases"), systemImage: "bag.badge.plus")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading).padding().kCard(16)
                }
                HStack {
                    TextField(store.t("Nhập Store ID (vd 12)", "Enter Store ID (e.g. 12)"), text: $searchId)
                        .keyboardType(.numberPad)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button(store.t("Xem", "View")) { Task { await findStore() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(searching || Int(searchId) == nil)
                }
                if searching { ProgressView() }
                if let e = searchError { Text(e).font(.caption).foregroundStyle(.red) }
                if let s = foundStore {
                    foundStorefront(s)
                    // Mở MẶT TIỀN đầy đủ của cửa hàng này (giống storefront admin)
                    NavigationLink {
                        VendorStorefrontView(sid: s.id).environmentObject(store)
                    } label: {
                        Label(store.t("Vào cửa hàng này", "Enter this store"), systemImage: "storefront.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 44)
                            .background(Theme.accent).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    // Thông báo chạy của cửa hàng (nếu bật)
                    if let st = foundSettings, st.announceEnabled, !st.announceText.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "megaphone.fill").foregroundStyle(Theme.gold)
                            Text(st.announceText).font(.caption.bold()).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Theme.gold.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let d = s.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                        Text("Store ID #\(s.id)").font(.caption2).foregroundStyle(Theme.accent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().kCard(16)
                    // Liên hệ người bán
                    if let st = foundSettings, !st.contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("Liên hệ người bán", "Contact seller")).font(.subheadline.bold())
                            ForEach(st.contacts) { c in
                                if let url = URL(string: c.url) {
                                    Link(destination: url) {
                                        Label(c.label.isEmpty ? c.url : c.label, systemImage: "bubble.left.and.text.bubble.right.fill")
                                            .font(.caption.bold())
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding().kCard(16)
                    }
                    // Flash sale đang chạy
                    if let st = foundSettings, st.flashEnabled, st.flashDiscount > 0,
                       (st.flashEnd == 0 || st.flashEnd > Int(Date().timeIntervalSince1970)) {
                        HStack {
                            Image(systemName: "bolt.fill").foregroundStyle(.white)
                            Text("\(st.flashTitle) · -\(st.flashDiscount)%").font(.caption.bold()).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text(store.t("Sản phẩm (\(foundProducts.count))", "Products (\(foundProducts.count))")).font(.subheadline.bold())
                    ForEach(foundProducts) { p in buyableRow(p, storeId: s.id) }
                }
            }
            .padding()
        }
    }

    // §7 Đợt C — Trình chỉnh hiệu ứng chữ TÊN + SLOGAN (giống cửa hàng admin)
    @ViewBuilder private var effectsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Hiệu ứng chữ (giống cửa hàng admin)", "Text effects (like admin store)"),
                  systemImage: "sparkles").font(.subheadline.bold())

            // Xem trước trực tiếp trên nền tối như hero storefront
            VStack(alignment: .leading, spacing: 4) {
                LogoEffectText(text: name.isEmpty ? store.t("Tên cửa hàng", "Store name") : name,
                               effect: nameEffect,
                               font: .title3.bold(),
                               solidColor: hexColor(nameColor))
                    .lineLimit(1)
                if !slogan.isEmpty {
                    LogoEffectText(text: slogan,
                                   effect: sloganEffect == "none" ? "solid" : sloganEffect,
                                   font: .caption.bold(),
                                   solidColor: hexColor(sloganColor) ?? .white.opacity(0.92))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Tên cửa hàng
            effectPicker(title: store.t("Hiệu ứng TÊN", "NAME effect"),
                         selection: $nameEffect, color: $nameColor)
            // Slogan
            effectPicker(title: store.t("Hiệu ứng SLOGAN", "SLOGAN effect"),
                         selection: $sloganEffect, color: $sloganColor)

            Text(store.t("Chọn \"Màu tự chọn 🎨\" để tự đặt màu chữ. Nhớ bấm \"Lưu thay đổi\" ở trên.",
                         "Pick \"Custom color 🎨\" to set your own. Remember to tap \"Save changes\" above."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding().kCard(16)
    }

    // 1 hàng chọn hiệu ứng + (nếu solid) chọn màu
    @ViewBuilder private func effectPicker(title: String,
                                           selection: Binding<String>,
                                           color: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kLogoEffects, id: \.0) { key, label in
                        Button {
                            selection.wrappedValue = key
                        } label: {
                            Text(label).font(.caption2.bold())
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selection.wrappedValue == key ? Theme.accent : Color(.secondarySystemBackground))
                                .foregroundStyle(selection.wrappedValue == key ? .white : .primary)
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if selection.wrappedValue == "solid" {
                ColorPicker(store.t("Màu chữ", "Text color"),
                            selection: Binding(
                                get: { hexColor(color.wrappedValue) ?? .white },
                                set: { color.wrappedValue = $0.hexStringRGB }),
                            supportsOpacity: false)
                    .font(.caption)
            }
        }
    }

    // Xem trước dáng cửa hàng: ảnh bìa + logo + tên + slogan (như storefront thật)
    @ViewBuilder private var storefrontPreview: some View {
        ZStack(alignment: .bottomLeading) {
            // Ảnh bìa
            Group {
                if !bannerUrl.isEmpty, let url = URL(string: bannerUrl) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Color(.tertiarySystemBackground) }
                } else {
                    LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.purple.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 130).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

            HStack(spacing: 10) {
                // Logo
                Group {
                    if !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                        CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { Color.black.opacity(0.3) }
                    } else {
                        ZStack { Color.black.opacity(0.3); Image(systemName: "storefront.fill").foregroundStyle(.white) }
                    }
                }
                .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.6), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? store.t("Tên cửa hàng", "Store name") : name)
                        .font(.headline).foregroundStyle(.white).lineLimit(1)
                    if !slogan.isEmpty {
                        Text(slogan).font(.caption2).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Đợt 3 — Bảng điều khiển người bán: doanh thu + đơn hàng + tồn kho
    @ViewBuilder private var sellerDashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.t("Doanh thu & Đơn hàng", "Revenue & Orders")).font(.subheadline.bold())
                Spacer()
                if let s = myStore {
                    NavigationLink {
                        SellerOrdersView(storeId: s.id).environmentObject(store)
                    } label: {
                        Label(store.t("Xem đơn", "Orders"), systemImage: "list.bullet.rectangle").font(.caption.bold())
                    }
                }
            }
            if let st = stats {
                HStack(spacing: 10) {
                    statBox(store.t("Doanh thu", "Revenue"), kFormatVND(st.revenueTotal), Theme.accent)
                    statBox(store.t("Đơn", "Orders"), "\(st.ordersTotal)", Theme.gold)
                }
                HStack(spacing: 10) {
                    statBox(store.t("Hôm nay", "Today"), kFormatVND(st.revenueToday), .green)
                    statBox(store.t("Key còn", "Keys left"), "\(st.keysAvailable)", .orange)
                }
                if !st.topProducts.isEmpty {
                    Text(store.t("Bán chạy", "Top sellers")).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(st.topProducts, id: \.self) { t in
                        HStack {
                            Text(t.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(store.t("\(t.sold) đơn", "\(t.sold) sold")).font(.caption2).foregroundStyle(.secondary)
                            Text(kFormatVND(t.revenue)).font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                    }
                }
                let lows = st.lowStock.filter { $0.stock == 0 }
                if !lows.isEmpty {
                    Text(store.t("⚠️ Hết kho: ", "⚠️ Out of stock: ") + lows.map(\.name).prefix(3).joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.orange).padding(.top, 2)
                }
            } else {
                Text(store.t("Chưa có dữ liệu bán hàng.", "No sales data yet."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding().kCard(16)
    }

    private func statBox(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Quản lý danh mục: thêm / xoá
    @ViewBuilder private var categoryManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("Danh mục (\(categories.count))", "Categories (\(categories.count))")).font(.subheadline.bold())
            if !categories.isEmpty {
                ForEach(categories) { c in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.gold)
                        Text(c.name).font(.subheadline)
                        Spacer()
                        Button(role: .destructive) {
                            Task { try? await store.api.deleteMyCategory(c.id); await loadMine() }
                        } label: { Image(systemName: "trash").font(.caption) }
                    }
                    .padding(8).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                TextField(store.t("Tên danh mục mới (vd: Game, App...)", "New category name..."), text: $newCatName)
                    .padding(8).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    let n = newCatName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    newCatName = ""
                    Task { try? await store.api.addMyCategory(name: n); await loadMine() }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding().kCard(16)
    }

    // Gom sản phẩm theo danh mục (mục "Chưa phân loại" cho cái chưa gắn)
    @ViewBuilder private var groupedProducts: some View {
        ForEach(categories) { c in
            let items = products.filter { ($0.categoryId ?? 0) == c.id }
            if !items.isEmpty {
                Text(c.name).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(items) { p in productRow(p, canDelete: true) }
            }
        }
        let unc = products.filter { p in !categories.contains { $0.id == (p.categoryId ?? 0) } }
        if !unc.isEmpty {
            if !categories.isEmpty {
                Text(store.t("Chưa phân loại", "Uncategorized")).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
            }
            ForEach(unc) { p in productRow(p, canDelete: true) }
        }
    }

    // Dáng cửa hàng của người khác khi xem theo Store ID (ảnh bìa + logo + tên + slogan)
    private func foundStorefront(_ s: MyStore) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let bu = s.bannerUrl, !bu.isEmpty, let url = URL(string: bu) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { Color(.tertiarySystemBackground) }
                } else {
                    LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.purple.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 130).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 10) {
                Group {
                    if let lu = s.logoUrl, !lu.isEmpty, let url = URL(string: lu) {
                        CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { Color.black.opacity(0.3) }
                    } else {
                        ZStack { Color.black.opacity(0.3); Image(systemName: "storefront.fill").foregroundStyle(.white) }
                    }
                }
                .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if let sl = s.slogan, !sl.isEmpty {
                        Text(sl).font(.caption2).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func productRow(_ p: MyStoreProduct, canDelete: Bool) -> some View {
        HStack(spacing: 10) {
            if let m = p.media?.first, let url = URL(string: m.url) {
                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color(.tertiarySystemBackground) }
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)).frame(width: 52, height: 52)
                    .overlay(Image(systemName: "bag").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.subheadline.bold()).lineLimit(1)
                if let d = p.description, !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                // Bảng giá nhiều mốc (nếu có) — hiện mốc thấp nhất → cao nhất
                if let prices = p.prices, !prices.isEmpty {
                    let lo = prices.map(\.amount).min() ?? p.price
                    let hi = prices.map(\.amount).max() ?? p.price
                    Text(lo == hi ? kFormatVND(lo) : "\(kFormatVND(lo)) – \(kFormatVND(hi))")
                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                    Text(store.t("\(prices.count) mốc giá", "\(prices.count) tiers"))
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(kFormatVND(p.price)).font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                // Tồn kho KEY
                if let stock = p.stock {
                    Text(store.t("Kho: \(stock) key", "Stock: \(stock) keys"))
                        .font(.caption2.bold())
                        .foregroundStyle(stock > 0 ? Color.green : Color.orange)
                }
            }
            Spacer(minLength: 0)
            if canDelete {
                Button { managingProduct = p } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.gold)
                }.buttonStyle(.plain).padding(.trailing, 4)
                Button { Task { try? await store.api.deleteMyProduct(p.id); await loadMine() } } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }.buttonStyle(.plain)
            }
        }
        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Đợt 3 — Sản phẩm khi xem shop người khác: có nút Mua
    private func buyableRow(_ p: MyStoreProduct, storeId: Int) -> some View {
        HStack(spacing: 10) {
            if let m = p.media?.first, let url = URL(string: m.url) {
                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color(.tertiarySystemBackground) }
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)).frame(width: 52, height: 52)
                    .overlay(Image(systemName: "bag").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.subheadline.bold()).lineLimit(1)
                if let d = p.description, !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                if let prices = p.prices, !prices.isEmpty {
                    let lo = prices.map(\.amount).min() ?? p.price
                    let hi = prices.map(\.amount).max() ?? p.price
                    Text(lo == hi ? kFormatVND(lo) : "\(kFormatVND(lo)) – \(kFormatVND(hi))")
                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                } else {
                    Text(kFormatVND(p.price)).font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 6) {
                    if let r = p.rating, let n = p.reviewCount, n > 0 {
                        Label(String(format: "%.1f", r), systemImage: "star.fill")
                            .font(.caption2).foregroundStyle(.yellow)
                        Text("(\(n))").font(.caption2).foregroundStyle(.secondary)
                    }
                    if p.kind == "acc" {
                        Text(store.t("Acc game", "Game acc")).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.purple.opacity(0.2)).clipShape(Capsule())
                    }
                    if let stock = p.stock, stock == 0 {
                        Text(store.t("Hết hàng", "Sold out")).font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { buyTarget = BuyTarget(product: p, storeId: storeId) } label: {
                Text(store.t("Mua", "Buy")).font(.caption.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accent).foregroundStyle(.white).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions
    private func loadMine() async {
        loading = true; defer { loading = false }
        if let r = try? await store.api.getMyStore() {
            myStore = r.store
            products = r.products ?? []
            categories = r.categories ?? []
            if let s = r.store {
                name = s.name; desc = s.description ?? ""
                slogan = s.slogan ?? ""
                logoUrl = s.logoUrl ?? ""
                bannerUrl = s.bannerUrl ?? ""
                nameEffect = s.nameEffect ?? "gradient"
                sloganEffect = s.sloganEffect ?? "none"
                nameColor = s.nameColor ?? ""
                sloganColor = s.sloganColor ?? ""
                stats = try? await store.api.myStoreStats()   // Đợt 3 — thống kê
            }
        }
    }

    // Upload logo hoặc ảnh bìa lên máy chủ → điền link
    private func uploadImage(_ item: PhotosPickerItem, isBanner: Bool) async {
        if isBanner { uploadingBanner = true } else { uploadingLogo = true }
        defer { if isBanner { uploadingBanner = false; bannerItem = nil }
                else { uploadingLogo = false; logoItem = nil } }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
        if let url = try? await store.api.mediaUpload(
            dataBase64: data.base64EncodedString(), mime: "image/jpeg",
            name: "\(isBanner ? "banner" : "logo")_\(Int(Date().timeIntervalSince1970)).jpg") {
            if isBanner { bannerUrl = url } else { logoUrl = url }
        }
    }

    private func saveStore() async {
        saving = true; defer { saving = false }
        message = nil; errorMessage = nil
        let wasNew = (myStore == nil)
        do {
            let s = try await store.api.saveMyStore(
                name: name.trimmingCharacters(in: .whitespaces),
                description: desc,
                logoUrl: logoUrl.isEmpty ? nil : logoUrl,
                bannerUrl: bannerUrl.isEmpty ? nil : bannerUrl,
                slogan: slogan,
                nameEffect: nameEffect,
                sloganEffect: sloganEffect,
                nameColor: nameEffect == "solid" ? nameColor : "",
                sloganColor: sloganEffect == "solid" ? sloganColor : "")
            myStore = s
            store.myStoreId = s.id
            message = store.t("Đã lưu cửa hàng ✅", "Store saved ✅")
            // §7 — Tạo shop MỚI xong → nhảy sang tab "Shop của tôi" (storefront).
            if wasNew {
                store.tab = 20
                dismiss()
            }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Đổi lỗi thô (vd "Not Found") thành thông báo dễ hiểu bằng tiếng Việt.
    private func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("not found") || raw.contains("404") {
            return store.t("Máy chủ chưa bật tính năng Cửa hàng của tôi. Vui lòng cập nhật máy chủ (chạy capnhat-vps.sh) rồi thử lại.",
                           "The server hasn't enabled My Store yet. Update the server (run capnhat-vps.sh) and try again.")
        }
        if raw.contains("unauthor") || raw.contains("401") || raw.contains("403") {
            return store.t("Bạn cần đăng nhập lại để tạo cửa hàng.", "Please sign in again to create a store.")
        }
        if raw.contains("could not connect") || raw.contains("offline") || raw.contains("network") || raw.contains("timed out") {
            return store.t("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.", "Can't reach the server. Check your connection and retry.")
        }
        return store.t("Tạo cửa hàng thất bại: ", "Failed to create store: ") + error.localizedDescription
    }

    private func findStore() async {
        guard let sid = Int(searchId) else { return }
        searching = true; defer { searching = false }
        searchError = nil; foundStore = nil; foundProducts = []; foundSettings = nil
        do {
            let r = try await store.api.getUserStore(sid)
            foundStore = r.store
            foundProducts = r.products ?? []
            foundSettings = r.settings
        } catch {
            searchError = store.t("Không tìm thấy cửa hàng với ID này.", "No store found with this ID.")
        }
    }
}

// §7 — Sheet thêm/sửa sản phẩm cửa hàng cá nhân
struct AddMyProductView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var categories: [MyStoreCategory] = []
    var onDone: () async -> Void

    @State private var name = ""
    @State private var priceText = ""
    @State private var desc = ""
    @State private var downloadUrl = ""
    @State private var imageItem: PhotosPickerItem?
    @State private var imageUrl = ""
    @State private var mediaType = "image"   // image | video (như admin)
    @State private var pasteLink = ""
    @State private var categoryId = 0
    @State private var kind = "app"   // app | acc
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Thông tin sản phẩm", "Product info")) {
                    Picker(store.t("Loại", "Type"), selection: $kind) {
                        Text(store.t("Key / Ứng dụng", "Key / App")).tag("app")
                        Text(store.t("Tài khoản game", "Game account")).tag("acc")
                    }.pickerStyle(.segmented)
                    TextField(store.t("Tên sản phẩm", "Product name"), text: $name)
                    TextField(store.t("Giá (VND)", "Price (VND)"), text: $priceText).keyboardType(.numberPad)
                    TextField(store.t("Mô tả", "Description"), text: $desc, axis: .vertical).lineLimit(1...4)
                    TextField(store.t("Link tải/giao hàng (tuỳ chọn)", "Download/delivery link (optional)"), text: $downloadUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !categories.isEmpty {
                        Picker(store.t("Danh mục", "Category"), selection: $categoryId) {
                            Text(store.t("Chưa phân loại", "Uncategorized")).tag(0)
                            ForEach(categories) { c in Text(c.name).tag(c.id) }
                        }
                    }
                }
                Section(store.t("Ảnh / Video sản phẩm", "Product image / video")) {
                    if !imageUrl.isEmpty {
                        // Xem trước ẢNH · VIDEO · GIF theo link (như admin).
                        Group {
                            if isVideoLink(imageUrl), let u = URL(string: imageUrl) {
                                LoopingVideoBackground(url: u, fit: true)
                            } else if let url = URL(string: imageUrl) {
                                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Color(.tertiarySystemBackground) }
                            }
                        }
                        .frame(height: 140).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    PhotosPicker(selection: $imageItem, matching: .any(of: [.images, .videos])) {
                        Label(uploading ? store.t("Đang tải lên…", "Uploading…")
                                        : store.t("Chọn ảnh / video từ máy", "Choose image / video"),
                              systemImage: "photo.on.rectangle").font(.subheadline)
                    }.disabled(uploading)
                    HStack {
                        TextField(store.t("Hoặc dán link ảnh/video", "Or paste image/video link"), text: $pasteLink)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(store.t("Dán", "Set")) {
                            let u = pasteLink.trimmingCharacters(in: .whitespaces)
                            if !u.isEmpty { imageUrl = u; mediaType = isVideoLink(u) ? "video" : "image"; pasteLink = "" }
                        }.font(.caption.bold()).disabled(pasteLink.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle(store.t("Thêm sản phẩm", "Add product"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.t("Huỷ", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Lưu", "Save")) { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: imageItem) { item in
                guard let item else { return }
                Task { await uploadImage(item) }
            }
        }
    }

    private func uploadImage(_ item: PhotosPickerItem) async {
        uploading = true; defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
        let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
        let mime = isVideo ? "video/mp4" : "image/jpeg"
        let ext = isVideo ? "mp4" : "jpg"
        if let url = try? await store.api.mediaUpload(
            dataBase64: data.base64EncodedString(), mime: mime,
            name: "prod_\(Int(Date().timeIntervalSince1970)).\(ext)") {
            imageUrl = url
            mediaType = isVideo ? "video" : "image"
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        error = nil
        let media: [[String: String]] = imageUrl.isEmpty ? [] : [["type": mediaType, "url": imageUrl]]
        do {
            try await store.api.saveMyProduct(
                id: nil, name: name.trimmingCharacters(in: .whitespaces),
                description: desc, price: Int(priceText) ?? 0,
                media: media, downloadUrl: downloadUrl.isEmpty ? nil : downloadUrl,
                categoryId: categoryId == 0 ? nil : categoryId, kind: kind)
            await onDone()
            dismiss()
        } catch {
            let raw = error.localizedDescription.lowercased()
            if raw.contains("not found") || raw.contains("404") {
                self.error = store.t("Máy chủ chưa bật tính năng Cửa hàng của tôi. Cập nhật máy chủ (capnhat-vps.sh) rồi thử lại.",
                                     "Server hasn't enabled My Store yet. Update the server (capnhat-vps.sh) and retry.")
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}

// §7 Đợt 2B — Quản lý giá nhiều mốc + kho KEY cho 1 sản phẩm (cửa hàng của tôi)
struct ManageMyProductView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let product: MyStoreProduct
    var onDone: () async -> Void

    struct PriceRow: Identifiable { let id = UUID(); var label: String; var amount: String }
    @State private var tiers: [PriceRow] = []
    @State private var keys: [MyStoreKey] = []
    @State private var available = 0
    @State private var newKeys = ""
    @State private var savingPrices = false
    @State private var addingKeys = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                // ---- Bảng giá nhiều mốc ----
                Section(store.t("Bảng giá (nhiều mốc)", "Price tiers")) {
                    ForEach($tiers) { $t in
                        HStack {
                            TextField(store.t("Tên mốc (vd: 1 ngày)", "Label (e.g. 1 day)"), text: $t.label)
                            TextField(store.t("Giá", "Price"), text: $t.amount)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                            Button(role: .destructive) {
                                tiers.removeAll { $0.id == t.id }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button {
                        tiers.append(PriceRow(label: "", amount: ""))
                    } label: { Label(store.t("Thêm mốc giá", "Add tier"), systemImage: "plus") }
                    Button {
                        Task { await savePrices() }
                    } label: {
                        Text(savingPrices ? store.t("Đang lưu…", "Saving…") : store.t("Lưu bảng giá", "Save tiers"))
                            .font(.subheadline.bold())
                    }.disabled(savingPrices)
                    Text(store.t("Để trống bảng giá nếu chỉ bán 1 giá cố định.",
                                 "Leave empty to sell at a single fixed price."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ---- Kho KEY ----
                Section(store.t("Kho KEY — còn \(available)", "KEY inventory — \(available) left")) {
                    TextEditor(text: $newKeys)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if newKeys.isEmpty {
                                Text(store.t("Mỗi dòng 1 key/tài khoản…", "One key/account per line…"))
                                    .font(.caption).foregroundStyle(.secondary).padding(6).allowsHitTesting(false)
                            }
                        }
                    Button {
                        Task { await addKeys() }
                    } label: {
                        Text(addingKeys ? store.t("Đang thêm…", "Adding…") : store.t("Thêm key vào kho", "Add keys"))
                            .font(.subheadline.bold())
                    }.disabled(addingKeys || newKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !keys.isEmpty {
                        ForEach(keys) { k in
                            HStack {
                                Image(systemName: k.status == "sold" ? "checkmark.seal.fill" : "key.fill")
                                    .foregroundStyle(k.status == "sold" ? .secondary : Theme.gold)
                                Text(k.keyText).font(.caption.monospaced()).lineLimit(1)
                                    .strikethrough(k.status == "sold")
                                Spacer()
                                if k.status != "sold" {
                                    Button(role: .destructive) {
                                        Task { try? await store.api.deleteMyKey(k.id); await reload() }
                                    } label: { Image(systemName: "trash").font(.caption) }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            Task { try? await store.api.deleteMyAvailableKeys(product.id); await reload() }
                        } label: { Text(store.t("Xoá tất cả key còn lại", "Delete all available keys")).font(.caption) }
                    }
                }

                if let error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Xong", "Done")) { Task { await onDone(); dismiss() } }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        // nạp lại giá từ sản phẩm truyền vào (lần đầu) + KEY từ máy chủ
        if tiers.isEmpty, let ps = product.prices, !ps.isEmpty {
            tiers = ps.map { PriceRow(label: $0.label, amount: String($0.amount)) }
        }
        if let r = try? await store.api.listMyProductKeys(product.id) {
            keys = r.keys; available = r.available; newKeys = ""
        }
        await onDone()   // để danh sách ngoài cập nhật tồn kho
    }

    private func savePrices() async {
        savingPrices = true; defer { savingPrices = false }
        error = nil
        let clean: [(label: String, amount: Int)] = tiers.compactMap {
            let l = $0.label.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, let a = Int($0.amount), a >= 0 else { return nil }
            return (l, a)
        }
        do {
            try await store.api.setMyProductPrices(product.id, prices: clean)
            await onDone()
        } catch { self.error = error.localizedDescription }
    }

    private func addKeys() async {
        addingKeys = true; defer { addingKeys = false }
        error = nil
        do {
            try await store.api.addMyProductKeys(product.id, text: newKeys, priceId: nil)
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}

// §7 Đợt 3 — Người bán: danh sách đơn hàng của cửa hàng mình
struct SellerOrdersView: View {
    @EnvironmentObject var store: AppStore
    let storeId: Int
    @State private var orders: [MyStoreOrder] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if orders.isEmpty {
                Text(store.t("Chưa có đơn hàng nào.", "No orders yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(o.productName).font(.subheadline.bold())
                            Spacer()
                            Text(kFormatVND(o.amount)).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                        }
                        HStack(spacing: 8) {
                            if !o.priceLabel.isEmpty {
                                Text(o.priceLabel).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.gold.opacity(0.2)).clipShape(Capsule())
                            }
                            Text(store.t("Người mua: ", "Buyer: ") + o.buyer).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(kStoreDate(o.createdAt)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(store.t("Đơn hàng", "Orders"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            orders = (try? await store.api.myStoreOrders()) ?? []
            loading = false
        }
    }
}

// §7 Đợt 3 — Người mua: chọn mốc giá và mua sản phẩm shop khác (trả bằng ví)
struct BuyProductView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let product: MyStoreProduct
    let storeId: Int

    @State private var selectedTier: Int = 0
    @State private var buying = false
    @State private var result: UStoreBuyResult?
    @State private var error: String?
    @State private var promoCode = ""
    @State private var discount = 0
    @State private var promoMsg: String?
    @State private var checkingPromo = false

    private var hasTiers: Bool { !(product.prices ?? []).isEmpty }
    private var baseAmount: Int {
        if hasTiers, let t = (product.prices ?? []).first(where: { $0.id == selectedTier }) { return t.amount }
        return product.price
    }
    private var amount: Int { max(0, baseAmount - discount) }

    var body: some View {
        NavigationStack {
            Form {
                if let r = result {
                    Section(store.t("Mua thành công 🎉", "Purchase complete 🎉")) {
                        if !r.key.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.t("KEY / Tài khoản của bạn:", "Your KEY / account:")).font(.caption).foregroundStyle(.secondary)
                                Text(r.key).font(.callout.monospaced()).textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = r.key
                                } label: { Label(store.t("Sao chép", "Copy"), systemImage: "doc.on.doc").font(.caption) }
                            }
                        }
                        if !r.downloadUrl.isEmpty, let u = URL(string: r.downloadUrl) {
                            Link(destination: u) { Label(store.t("Mở link tải/giao hàng", "Open delivery link"), systemImage: "arrow.down.circle") }
                        }
                        Text(store.t("Số dư ví còn: ", "Wallet balance: ") + kFormatVND(r.balance)).font(.caption).foregroundStyle(.secondary)
                        Text(store.t("Xem lại trong \"Đơn đã mua của tôi\".", "Find it again in \"My purchases\".")).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Section(product.name) {
                        if let d = product.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                        if hasTiers {
                            Picker(store.t("Chọn mốc", "Choose tier"), selection: $selectedTier) {
                                ForEach(product.prices ?? []) { t in
                                    Text("\(t.label) — \(kFormatVND(t.amount))").tag(t.id)
                                }
                            }
                            .onChange(of: selectedTier) { _ in discount = 0; promoMsg = nil }
                        }
                        // Mã giảm giá
                        HStack {
                            TextField(store.t("Mã giảm giá (nếu có)", "Promo code (optional)"), text: $promoCode)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            Button {
                                Task { await checkPromo() }
                            } label: {
                                Text(checkingPromo ? "…" : store.t("Áp dụng", "Apply")).font(.caption.bold())
                            }.disabled(checkingPromo || promoCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let promoMsg { Text(promoMsg).font(.caption2).foregroundStyle(discount > 0 ? .green : .red) }
                        if discount > 0 {
                            HStack {
                                Text(store.t("Tạm tính", "Subtotal")).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(kFormatVND(baseAmount)).font(.caption).strikethrough().foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(store.t("Giảm giá", "Discount")).font(.caption).foregroundStyle(.green)
                                Spacer()
                                Text("-" + kFormatVND(discount)).font(.caption).foregroundStyle(.green)
                            }
                        }
                        HStack {
                            Text(store.t("Thanh toán", "Total")).font(.subheadline)
                            Spacer()
                            Text(kFormatVND(amount)).font(.headline).foregroundStyle(Theme.accent)
                        }
                    }
                    if let error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
                    Section {
                        Button {
                            Task { await buy() }
                        } label: {
                            HStack {
                                if buying { ProgressView().tint(.white) }
                                Text(store.t("Mua ngay (trừ ví)", "Buy now (from wallet)")).bold()
                            }.frame(maxWidth: .infinity)
                        }
                        .disabled(buying || (hasTiers && selectedTier == 0))
                        .listRowBackground(Theme.accent)
                        .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle(result == nil ? store.t("Mua hàng", "Buy") : store.t("Hoàn tất", "Done"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(result == nil ? store.t("Huỷ", "Cancel") : store.t("Xong", "Done")) { dismiss() }
                }
            }
            .onAppear {
                if hasTiers, selectedTier == 0, let first = (product.prices ?? []).first { selectedTier = first.id }
            }
        }
    }

    private func buy() async {
        buying = true; defer { buying = false }
        error = nil
        do {
            result = try await store.api.buyUserStore(
                sid: storeId, productId: product.id,
                priceId: hasTiers ? selectedTier : nil,
                promoCode: discount > 0 ? promoCode.trimmingCharacters(in: .whitespaces) : nil)
        } catch { self.error = error.localizedDescription }
    }

    private func checkPromo() async {
        checkingPromo = true; defer { checkingPromo = false }
        let code = promoCode.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            let r = try await store.api.validateUStorePromo(sid: storeId, code: code, amount: baseAmount)
            discount = r.discount
            promoMsg = discount > 0
                ? store.t("Đã giảm \(kFormatVND(discount))", "Saved \(kFormatVND(discount))")
                : store.t("Mã không giảm cho đơn này.", "No discount for this order.")
        } catch {
            discount = 0
            promoMsg = error.localizedDescription
        }
    }
}

// §7 Đợt 3 — Người mua: các đơn đã mua từ cửa hàng cá nhân (lấy lại key)
struct MyPurchasesView: View {
    @EnvironmentObject var store: AppStore
    @State private var orders: [UStoreMyOrder] = []
    @State private var loading = true
    @State private var reviewTarget: UStoreMyOrder?

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if orders.isEmpty {
                Text(store.t("Bạn chưa mua sản phẩm nào.", "You haven't bought anything yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(o.productName).font(.subheadline.bold())
                            Spacer()
                            Text(kFormatVND(o.amount)).font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                        Text("\(o.storeName)\(o.priceLabel.isEmpty ? "" : " • " + o.priceLabel)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !o.keyText.isEmpty {
                            HStack {
                                Text(o.keyText).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = o.keyText
                                } label: { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain)
                            }
                            .padding(6).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if !o.downloadUrl.isEmpty, let u = URL(string: o.downloadUrl) {
                            Link(destination: u) { Label(store.t("Mở link tải", "Open link"), systemImage: "arrow.down.circle").font(.caption) }
                        }
                        if o.productId > 0 {
                            Button { reviewTarget = o } label: {
                                Label(store.t("Đánh giá", "Review"), systemImage: "star").font(.caption)
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(store.t("Đơn đã mua", "My purchases"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewTarget) { o in
            ReviewProductView(storeId: o.storeId, productId: o.productId, productName: o.productName)
                .environmentObject(store)
        }
        .task {
            orders = (try? await store.api.myUserStoreOrders()) ?? []
            loading = false
        }
    }
}

// §7 Đợt 4 — Ví người bán: xem số dư + rút tiền + lịch sử + cài đặt thanh toán
struct SellerWalletView: View {
    @EnvironmentObject var store: AppStore
    let storeId: Int
    @State private var wallet: MyStoreWallet?
    @State private var amountText = ""
    @State private var bankInfo = ""
    @State private var submitting = false
    @State private var message: String?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(store.t("Số dư ví", "Balance")).font(.subheadline)
                    Spacer()
                    Text(kFormatVND(wallet?.balance ?? 0)).font(.title3.bold()).foregroundStyle(Theme.accent)
                }
                if let p = wallet?.pendingWithdraw, p > 0 {
                    HStack {
                        Text(store.t("Đang chờ rút", "Pending")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(kFormatVND(p)).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            // Cài đặt thanh toán riêng (giống hệt admin: ngân hàng + API tự động)
            Section {
                NavigationLink {
                    StorePaymentSettingsView(storeId: storeId).environmentObject(store)
                } label: {
                    Label(store.t("Thông tin ngân hàng & API tự động", "Bank info & auto API"),
                          systemImage: "building.columns")
                }
            } footer: {
                Text(store.t("Đặt ngân hàng nhận tiền và liên kết API giao dịch tự động (ACB thueapibank / Casso / Sepay) — riêng cho cửa hàng của bạn.",
                             "Set your receiving bank and link an auto-transaction API (ACB thueapibank / Casso / Sepay) — just for your store."))
                    .font(.caption2)
            }
            Section(store.t("Yêu cầu rút tiền", "Withdraw")) {
                TextField(store.t("Số tiền (tối thiểu 50.000đ)", "Amount (min 50,000đ)"), text: $amountText)
                    .keyboardType(.numberPad)
                TextField(store.t("Ngân hàng · Số TK · Chủ TK", "Bank · Account · Name"), text: $bankInfo, axis: .vertical)
                    .lineLimit(1...3)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if let message { Text(message).foregroundStyle(.green).font(.caption) }
                Button {
                    Task { await submit() }
                } label: {
                    Text(submitting ? store.t("Đang gửi…", "Sending…") : store.t("Gửi yêu cầu rút", "Request withdrawal"))
                        .font(.subheadline.bold())
                }.disabled(submitting || (Int(amountText) ?? 0) < 50000 || bankInfo.trimmingCharacters(in: .whitespaces).isEmpty)
                Text(store.t("Tiền chờ duyệt sẽ tạm giữ khỏi ví. Nếu bị từ chối sẽ hoàn lại.",
                             "Pending amount is held from your wallet; refunded if rejected."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let ws = wallet?.withdrawals, !ws.isEmpty {
                Section(store.t("Lịch sử rút", "History")) {
                    ForEach(ws) { w in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(kFormatVND(w.amount)).font(.subheadline.bold())
                                Spacer()
                                Text(statusLabel(w.status)).font(.caption.bold()).foregroundStyle(statusColor(w.status))
                            }
                            Text(w.bankInfo).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            Text(kStoreDate(w.createdAt)).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(store.t("Ví & Rút tiền", "Wallet"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "paid": return store.t("Đã chi", "Paid")
        case "rejected": return store.t("Từ chối", "Rejected")
        default: return store.t("Chờ duyệt", "Pending")
        }
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "paid": return .green; case "rejected": return .red; default: return .orange }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        wallet = try? await store.api.myStoreWallet()
    }
    private func submit() async {
        submitting = true; defer { submitting = false }
        error = nil; message = nil
        do {
            try await store.api.requestWithdraw(amount: Int(amountText) ?? 0,
                                                bankInfo: bankInfo.trimmingCharacters(in: .whitespaces))
            message = store.t("Đã gửi yêu cầu rút tiền.", "Withdrawal requested.")
            amountText = ""; bankInfo = ""
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}

// §7 Đợt 4 — Cài đặt thanh toán RIÊNG của cửa hàng (giống hệt admin: ngân hàng + API tự động + QR)
struct StorePaymentSettingsView: View {
    @EnvironmentObject var store: AppStore
    let storeId: Int
    @State private var s = BankSettings(bankCode: "", bankShort: "", bankAccount: "", bankName: "",
                                        bankWebhook: "", bankApikey: "", acbApiToken: "")
    @State private var qr: StorePaymentInfo?
    @State private var message: String?
    @State private var isError = false
    @State private var saving = false

    var body: some View {
        Form {
            Section(store.t("Ngân hàng nhận tiền (hiện QR cho khách khi mua)", "Receiving bank (buyer QR)")) {
                TextField(store.t("Mã ngân hàng VietQR (vd ACB = 970416)", "VietQR bank code (ACB = 970416)"), text: $s.bankCode)
                    .keyboardType(.numberPad)
                TextField(store.t("Tên ngân hàng ngắn (vd ACB)", "Short bank name (e.g. ACB)"), text: $s.bankShort)
                    .textInputAutocapitalization(.characters)
                TextField(store.t("Số tài khoản", "Account number"), text: $s.bankAccount).keyboardType(.numberPad)
                TextField(store.t("Chủ tài khoản (IN HOA, không dấu)", "Account holder (UPPERCASE, no accents)"), text: $s.bankName)
                    .textInputAutocapitalization(.characters)
                TextField(store.t("Webhook (tuỳ chọn)", "Webhook (optional)"), text: $s.bankWebhook)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section(store.t("Nạp/thu tiền tự động — ACB (thueapibank.vn)", "Auto payment — ACB (thueapibank.vn)")) {
                TextField(store.t("API token ACB (thueapibank.vn)", "ACB API token (thueapibank.vn)"), text: $s.acbApiToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(store.t("Dán API token ACB từ thueapibank.vn. Hệ thống đọc lịch sử giao dịch, khớp nội dung + số tiền để tự xác nhận đơn cho cửa hàng bạn. Để trống thì xác nhận tay.",
                             "Paste your ACB API token from thueapibank.vn. The system reads transactions and auto-confirms orders for your store. Leave empty for manual confirm."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(store.t("Tự động xác nhận giao dịch (tuỳ chọn khác)", "Auto-confirm (other option)")) {
                TextField(store.t("API key giao dịch (Casso / Sepay...)", "Transaction API key (Casso / Sepay...)"), text: $s.bankApikey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(store.t("Dùng webhook của Casso/Sepay nếu muốn. Để trống nếu đã dùng token ACB ở trên.",
                             "Use Casso/Sepay webhook if you like. Leave empty if you already use the ACB token above."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await save() }
                } label: { Text(saving ? store.t("Đang lưu…", "Saving…") : store.t("Lưu", "Save")).font(.subheadline.bold()) }
                    .disabled(saving)
                if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
            }
            // Xem trước QR nhận tiền của chính cửa hàng
            if let q = qr, let url = URL(string: q.qrUrl) {
                Section(store.t("QR nhận tiền của cửa hàng", "Your store QR")) {
                    HStack {
                        Spacer()
                        CachedAsyncImage(url: url) { img in img.resizable().scaledToFit() }
                            placeholder: { ProgressView() }
                            .frame(width: 200, height: 200)
                        Spacer()
                    }
                    Text("\(q.bank) · \(q.account) · \(q.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(store.t("Mã VietQR (Napas): ACB 970416 · Vietcombank 970436 · Techcombank 970407 · MB 970422 · BIDV 970418 · VPBank 970432.",
                             "VietQR (Napas) codes: ACB 970416 · Vietcombank 970436 · Techcombank 970407 · MB 970422 · BIDV 970418 · VPBank 970432."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.t("Thông tin ngân hàng", "Bank info"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if let r = try? await store.api.getMyStorePayment() { s = r }
        qr = try? await store.api.userStorePaymentInfo(sid: storeId)
    }
    private func save() async {
        saving = true; defer { saving = false }
        message = nil
        do {
            try await store.api.saveMyStorePayment(s)
            isError = false; message = store.t("Đã lưu thông tin thanh toán.", "Payment info saved.")
            qr = try? await store.api.userStorePaymentInfo(sid: storeId)
        } catch { isError = true; message = error.localizedDescription }
    }
}

// §7 Đợt 4 — Quản lý mã giảm giá của cửa hàng
struct PromoManagerView: View {
    @EnvironmentObject var store: AppStore
    @State private var promos: [MyStorePromo] = []
    @State private var code = ""
    @State private var isPercent = true
    @State private var valueText = ""
    @State private var minText = ""
    @State private var maxUsesText = ""
    @State private var creating = false
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Form {
            Section(store.t("Tạo mã mới", "New code")) {
                TextField(store.t("Mã (vd GIAM10)", "Code (e.g. SAVE10)"), text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Picker(store.t("Kiểu giảm", "Type"), selection: $isPercent) {
                    Text(store.t("Theo %", "Percent")).tag(true)
                    Text(store.t("Số tiền", "Fixed")).tag(false)
                }.pickerStyle(.segmented)
                TextField(isPercent ? store.t("Phần trăm giảm (1–100)", "Percent (1–100)")
                                    : store.t("Số tiền giảm (VND)", "Amount off (VND)"), text: $valueText)
                    .keyboardType(.numberPad)
                TextField(store.t("Đơn tối thiểu (tuỳ chọn)", "Min order (optional)"), text: $minText)
                    .keyboardType(.numberPad)
                TextField(store.t("Giới hạn lượt dùng (0 = vô hạn)", "Max uses (0 = unlimited)"), text: $maxUsesText)
                    .keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Button {
                    Task { await create() }
                } label: {
                    Text(creating ? store.t("Đang tạo…", "Creating…") : store.t("Tạo mã", "Create code"))
                        .font(.subheadline.bold())
                }.disabled(creating || code.trimmingCharacters(in: .whitespaces).isEmpty || (Int(valueText) ?? 0) <= 0)
            }
            Section(store.t("Mã hiện có (\(promos.count))", "Codes (\(promos.count))")) {
                if promos.isEmpty {
                    Text(store.t("Chưa có mã nào.", "No codes yet.")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(promos) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.code).font(.subheadline.bold().monospaced())
                            Text(p.discountType == "percent" ? "-\(p.discountValue)%" : "-" + kFormatVND(p.discountValue))
                                .font(.caption.bold()).foregroundStyle(Theme.accent)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { p.isActive == 1 },
                                set: { _ in Task { try? await store.api.toggleMyPromo(p.id); await reload() } }
                            )).labelsHidden()
                        }
                        HStack(spacing: 8) {
                            if p.minAmount > 0 { Text(store.t("Tối thiểu ", "Min ") + kFormatVND(p.minAmount)).font(.caption2).foregroundStyle(.secondary) }
                            Text(store.t("Đã dùng: \(p.usedCount)\(p.maxUses > 0 ? "/\(p.maxUses)" : "")",
                                         "Used: \(p.usedCount)\(p.maxUses > 0 ? "/\(p.maxUses)" : "")"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { try? await store.api.deleteMyPromo(p.id); await reload() }
                        } label: { Label(store.t("Xoá", "Delete"), systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(store.t("Mã giảm giá", "Promo codes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        promos = (try? await store.api.myStorePromos()) ?? []
    }
    private func create() async {
        creating = true; defer { creating = false }
        error = nil
        do {
            try await store.api.createMyPromo(
                code: code.trimmingCharacters(in: .whitespaces).uppercased(),
                discountType: isPercent ? "percent" : "fixed",
                discountValue: Int(valueText) ?? 0,
                minAmount: Int(minText) ?? 0,
                maxUses: Int(maxUsesText) ?? 0,
                expiresAt: 0)
            code = ""; valueText = ""; minText = ""; maxUsesText = ""
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}

// §7 Đợt 5 — Cài đặt hiển thị cửa hàng: thông báo chạy · flash sale · liên hệ
struct StoreStorefrontSettingsView: View {
    @EnvironmentObject var store: AppStore
    let products: [MyStoreProduct]

    @State private var announceEnabled = false
    @State private var announceText = ""
    @State private var flashEnabled = false
    @State private var flashProductId = 0
    @State private var flashDiscount = ""
    @State private var flashTitle = "FLASH SALE"
    @State private var flashEndDate = Date().addingTimeInterval(3600)
    @State private var contacts: [StoreContactLink] = []
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            // Thông báo chạy
            Section(store.t("Thông báo chạy đầu cửa hàng", "Announcement bar")) {
                Toggle(store.t("Bật thông báo", "Enable"), isOn: $announceEnabled)
                TextField(store.t("Nội dung (vd: Sale 20% cuối tuần!)", "Text (e.g. 20% off weekend!)"),
                          text: $announceText, axis: .vertical).lineLimit(1...3)
            }
            // Flash sale
            Section(store.t("Flash sale (đếm ngược giảm giá)", "Flash sale")) {
                Toggle(store.t("Bật flash sale", "Enable flash sale"), isOn: $flashEnabled)
                if flashEnabled {
                    Picker(store.t("Sản phẩm", "Product"), selection: $flashProductId) {
                        Text(store.t("— Chọn —", "— Pick —")).tag(0)
                        ForEach(products) { p in Text(p.name).tag(p.id) }
                    }
                    TextField(store.t("% giảm (1–100)", "Discount % (1–100)"), text: $flashDiscount)
                        .keyboardType(.numberPad)
                    TextField(store.t("Tiêu đề", "Title"), text: $flashTitle)
                    DatePicker(store.t("Kết thúc lúc", "Ends at"), selection: $flashEndDate)
                }
            }
            // Liên hệ người bán
            Section(store.t("Liên hệ người bán (khách bấm để chat)", "Seller contacts")) {
                ForEach($contacts) { $c in
                    VStack(spacing: 4) {
                        HStack {
                            TextField(store.t("Tên (Zalo, Facebook…)", "Label (Zalo, Facebook…)"), text: $c.label)
                            Toggle("", isOn: $c.enabled).labelsHidden()
                        }
                        TextField(store.t("Link (https://…)", "Link (https://…)"), text: $c.url)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption)
                    }
                }
                .onDelete { contacts.remove(atOffsets: $0) }
                Button {
                    contacts.append(StoreContactLink(label: "", url: "", enabled: true))
                } label: { Label(store.t("Thêm liên hệ", "Add contact"), systemImage: "plus") }
            }
            Section {
                Button {
                    Task { await save() }
                } label: { Text(saving ? store.t("Đang lưu…", "Saving…") : store.t("Lưu cài đặt", "Save")).font(.subheadline.bold()) }
                    .disabled(saving)
                if let message { Text(message).font(.caption).foregroundStyle(isError ? .red : .green) }
            }
        }
        .navigationTitle(store.t("Cài đặt cửa hàng", "Storefront settings"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let s = try? await store.api.getMyStoreSettings() else { return }
        announceEnabled = s.announceEnabled; announceText = s.announceText
        flashEnabled = s.flashEnabled; flashProductId = s.flashProductId
        flashDiscount = s.flashDiscount > 0 ? String(s.flashDiscount) : ""
        flashTitle = s.flashTitle
        if s.flashEnd > 0 { flashEndDate = Date(timeIntervalSince1970: TimeInterval(s.flashEnd)) }
        contacts = s.contacts
    }
    private func save() async {
        saving = true; defer { saving = false }
        message = nil
        do {
            try await store.api.saveMyStoreSettings(
                announceEnabled: announceEnabled, announceText: announceText.trimmingCharacters(in: .whitespacesAndNewlines),
                flashEnabled: flashEnabled, flashProductId: flashProductId,
                flashEnd: flashEnabled ? Int(flashEndDate.timeIntervalSince1970) : 0,
                flashDiscount: Int(flashDiscount) ?? 0, flashTitle: flashTitle.trimmingCharacters(in: .whitespaces),
                contacts: contacts.filter { !$0.label.isEmpty || !$0.url.isEmpty })
            isError = false; message = store.t("Đã lưu cài đặt cửa hàng.", "Storefront settings saved.")
        } catch { isError = true; message = error.localizedDescription }
    }
}

// §7 Đợt 5 — Đánh giá sản phẩm đã mua
struct ReviewProductView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let storeId: Int
    let productId: Int
    let productName: String

    @State private var rating = 5
    @State private var comment = ""
    @State private var reviews: [MyStoreReview] = []
    @State private var avg = 0.0
    @State private var count = 0
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Chấm điểm", "Your rating")) {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .foregroundStyle(.yellow).font(.title3)
                                .onTapGesture { rating = i }
                        }
                    }
                    TextField(store.t("Nhận xét (tuỳ chọn)", "Comment (optional)"), text: $comment, axis: .vertical)
                        .lineLimit(1...4)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button {
                        Task { await submit() }
                    } label: { Text(submitting ? store.t("Đang gửi…", "Sending…") : store.t("Gửi đánh giá", "Submit")).bold() }
                        .disabled(submitting)
                }
                if count > 0 {
                    Section(store.t("Đánh giá (\(count)) · TB \(String(format: "%.1f", avg))★",
                                    "Reviews (\(count)) · avg \(String(format: "%.1f", avg))★")) {
                        ForEach(reviews) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(r.username).font(.caption.bold())
                                    Spacer()
                                    Text(String(repeating: "★", count: r.rating)).font(.caption).foregroundStyle(.yellow)
                                }
                                if !r.comment.isEmpty { Text(r.comment).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(productName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await loadReviews() }
        }
    }

    private func loadReviews() async {
        if let r = try? await store.api.userStoreReviews(sid: storeId, pid: productId) {
            reviews = r.reviews; avg = r.rating; count = r.count
        }
    }
    private func submit() async {
        submitting = true; defer { submitting = false }
        error = nil
        do {
            try await store.api.postUserStoreReview(sid: storeId, pid: productId, rating: rating, comment: comment)
            comment = ""
            await loadReviews()
        } catch { self.error = error.localizedDescription }
    }
}

// Định dạng ngày ngắn cho đơn hàng cửa hàng cá nhân
private func kStoreDate(_ ts: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "dd/MM HH:mm"
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
}
