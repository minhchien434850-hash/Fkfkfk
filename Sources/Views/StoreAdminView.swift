import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// Media có thể chỉnh sửa (admin) — link ảnh/video, tối đa 5
struct EditMedia: Identifiable, Hashable {
    let id = UUID()
    var type: String = "image"   // image | video
    var url: String = ""
}

func editMediaToPayload(_ items: [EditMedia]) -> [[String: String]] {
    items.prefix(5).filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { ["type": $0.type, "url": $0.url.trimmingCharacters(in: .whitespaces)] }
}

func mediaToEdit(_ items: [StoreMedia]) -> [EditMedia] {
    items.map { EditMedia(type: $0.type, url: $0.url) }
}

// Trình chỉnh sửa media dùng chung (tối đa 5) — hỗ trợ GIF/PNG/JPEG/WEBP/MP4
struct MediaEditor: View {
    @Binding var media: [EditMedia]
    @EnvironmentObject var store: AppStore
    @State private var showConverter = false
    @State private var picker: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadError: String?

    var body: some View {
        Section {
            ForEach($media) { $m in
                VStack(alignment: .leading, spacing: 6) {
                    Picker(store.t("Loại", "Type"), selection: $m.type) {
                        Text("Ảnh / GIF").tag("image")
                        Text("Video").tag("video")
                    }.pickerStyle(.segmented)
                    TextField(store.t("Dán link ảnh / GIF / PNG / JPEG / WEBP / MP4...", "Paste image / GIF / PNG / JPEG / WEBP / MP4 link..."), text: $m.url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .onDelete { media.remove(atOffsets: $0) }

            // Tải ảnh/video TRỰC TIẾP từ máy → tự lên máy chủ → tự điền link
            if media.count < 5 {
                PhotosPicker(selection: $picker, matching: .any(of: [.images, .videos])) {
                    HStack {
                        if uploading { ProgressView().padding(.trailing, 4) }
                        Label(uploading ? "Đang tải lên..." : "Chọn ảnh / video từ máy",
                              systemImage: "photo.badge.plus")
                    }
                }
                .disabled(uploading)

                Button { media.append(EditMedia()) } label: {
                    Label(store.t("Thêm ô dán link thủ công", "Add manual link field"), systemImage: "plus.circle")
                }
            }
            Button {
                showConverter = true
            } label: {
                Label(store.t("Chuyển đổi ảnh → link GIF / PNG / JPEG", "Convert image → GIF / PNG / JPEG link"), systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(store.accentColor)
            }
            // Gắn .sheet vào chính nút (không gắn vào Section) để mở được màn Chuyển đổi
            .sheet(isPresented: $showConverter) {
                MediaConverterView().environmentObject(store)
            }
            if let uploadError {
                Text(uploadError).font(.caption2).foregroundStyle(.red)
            }
        } header: {
            Text(store.t("Ảnh / Video (tối đa 5)", "Photo / Video (max 5)"))
        } footer: {
            Text(store.t("Chọn ảnh/video từ máy để tự tải lên, hoặc dán link từ Imgur, Cloudinary, Giphy... Hoặc bấm \"Chuyển đổi\" để tạo link từ ảnh.",
                         "Pick image/video from device to auto-upload, or paste a link from Imgur, Cloudinary, Giphy... Or tap \"Convert\" to make a link from an image."))
                .font(.caption2)
        }
        .onChange(of: picker) { item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        uploading = true; uploadError = nil
        defer { uploading = false; picker = nil }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        do {
            if isVideo {
                guard let movie = try await item.loadTransferable(type: EditMovie.self),
                      let data = try? Data(contentsOf: movie.url) else {
                    uploadError = "Không đọc được video."; return
                }
                let url = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(),
                    mime: "video/mp4", name: "v_\(Int(Date().timeIntervalSince1970)).mp4")
                if media.count < 5 { media.append(EditMedia(type: "video", url: url)) }
            } else {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    uploadError = "Không đọc được ảnh."; return
                }
                let url = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(),
                    mime: "image/jpeg", name: "i_\(Int(Date().timeIntervalSince1970)).jpg")
                if media.count < 5 { media.append(EditMedia(type: "image", url: url)) }
            }
        } catch { uploadError = error.localizedDescription }
    }
}

// ============================ Trang quản trị cửa hàng ============================
struct StoreAdminView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var categories: [StoreCategory] = []
    @State private var loading = false
    @State private var error: String?
    @State private var editCategory: StoreCategory?
    @State private var newCategory = false
    @State private var quickAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StoreConfigEditor()
                    } label: {
                        Label(store.t("Giao diện cửa hàng (logo, nền)", "Store appearance (logo, background)"), systemImage: "paintpalette")
                    }
                    NavigationLink {
                        StoreContactsEditor()
                    } label: {
                        Label(store.t("Liên hệ admin & Nhóm cộng đồng", "Admin contact & Community groups"), systemImage: "bubble.left.and.text.bubble.right")
                    }
                    NavigationLink {
                        StoreTopupBonusEditor()
                    } label: {
                        Label(store.t("Khuyến mãi (%)", "Promotions (%)"), systemImage: "percent")
                    }
                    NavigationLink {
                        StoreInventoryView()
                    } label: {
                        Label(store.t("Kho hàng (tồn kho)", "Inventory (stock)"), systemImage: "shippingbox")
                    }
                    NavigationLink {
                        StoreAdminOrdersView()
                    } label: {
                        Label(store.t("Đơn hàng đã bán", "Completed orders"), systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        AdminAnalyticsView()
                    } label: {
                        Label(store.t("Thống kê & Phân tích", "Statistics & Analytics"), systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        AdminPromoCodesView()
                    } label: {
                        Label(store.t("Mã khuyến mãi", "Promo codes"), systemImage: "tag.fill")
                    }
                    NavigationLink {
                        AdminPushNotificationView()
                    } label: {
                        Label(store.t("Gửi thông báo (Push)", "Send notification (Push)"), systemImage: "bell.badge.fill")
                    }
                    NavigationLink {
                        AdminWalletAdjustView()
                    } label: {
                        Label(store.t("Nạp / Trừ ví khách hàng", "Add / Deduct customer wallet"), systemImage: "dollarsign.arrow.circlepath")
                    }
                }

                Section(store.t("Danh mục sản phẩm", "Product categories") + " (\(categories.count))") {
                    ForEach(categories) { cat in
                        NavigationLink {
                            StoreAdminFolderList(category: cat)
                        } label: {
                            HStack(spacing: 10) {
                                // Thumbnail danh mục
                                if let m = cat.media.first, m.type != "video", let url = URL(string: m.url) {
                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                    placeholder: { Color(.tertiarySystemBackground) }
                                        .frame(width: 38, height: 38)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Theme.gold)
                                        .frame(width: 38, height: 38)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.name).font(.subheadline.bold())
                                    Text(store.t("Bấm để quản lý thư mục con", "Tap to manage subfolders"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { editCategory = cat } label: {
                                    Image(systemName: "pencil.circle")
                                        .foregroundStyle(.secondary)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                    .onDelete { idx in
                        Task { await deleteCategories(idx) }
                    }
                    Button { quickAdd = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .font(.title3).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.t("➕ Thêm sản phẩm (tất cả trong 1)", "➕ Add product (all-in-one)"))
                                    .font(.headline).foregroundStyle(.primary)
                                Text(store.t("Tạo danh mục, thư mục con, sản phẩm, giá & nhập key — tất cả trong 1 màn.",
                                             "Create category, subfolder, product, prices & keys — all in one screen."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle(store.t("Quản trị cửa hàng", "Store admin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(isPresented: $quickAdd) {
                StoreQuickAddView { Task { await reload() } }
            }
            .sheet(isPresented: $newCategory) {
                StoreCategoryEditor(category: nil) { Task { await reload() } }
            }
            .sheet(item: $editCategory) { cat in
                StoreCategoryEditor(category: cat) { Task { await reload() } }
            }
        }
    }

    private func reload() async {
        loading = true; error = nil
        do { categories = try await store.api.storeCategories() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func deleteCategories(_ idx: IndexSet) async {
        for i in idx {
            let cat = categories[i]
            _ = try? await store.api.adminStoreDeleteCategory(cat.id)
        }
        await reload()
    }
}

// ---- Giao diện cửa hàng ----
struct StoreConfigEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var logoName = ""
    @State private var logoUrl = ""
    @State private var bannerType = "image"
    @State private var bannerUrl = ""
    @State private var logoEffect = "rainbow"
    @State private var logoFont = "rounded"
    @State private var logoAnim = "shimmer"
    @State private var bgType = "none"
    @State private var bgUrl = ""
    @State private var slogan = ""
    @State private var sloganFont = "rounded"
    @State private var cardSize = "medium"
    @State private var cardScale: Double = 1.0
    @State private var sections: [String] = ["announce", "categories", "gamecat", "flash", "trust", "steps", "leaderboard",
                                             "transactions", "topups", "downloads", "contacts", "wishlist", "recent", "products", "footer"]
    @State private var hiddenSections: Set<String> = ["products"]
    // Thanh thông báo + số sản phẩm/danh mục
    @State private var announceEnabled = false
    @State private var announceText = ""
    @State private var announceColor = "accent"
    @State private var gamecatLimit = 6
    // Flash sale
    @State private var flashEnabled = false
    @State private var flashProductId = 0
    @State private var flashDiscount = 0
    @State private var flashEnd = Date().addingTimeInterval(3 * 86400)
    @State private var flashTitle = "FLASH SALE"
    @State private var heroTitle = ""
    @State private var heroSubtitle = ""
    @State private var heroEffect = "gradient"
    @State private var heroFont = "rounded-bold"
    @State private var heroAnim = "none"
    @State private var sloganEffect = "none"
    @State private var sloganAnim = "none"
    @State private var promoImageUrl = ""
    @State private var promoProductId = 0
    @State private var statUsersBase = 0
    @State private var statSoldBase = 0
    @State private var statReviewsBase = 0
    @State private var message: String?
    @State private var isError = false
    @AppStorage("storeCfgName") private var cfgName: String = ""
    @AppStorage("storeCfgLogo") private var cfgLogo: String = ""
    @AppStorage("storeCfgBannerType") private var cfgBannerType: String = "image"
    @AppStorage("storeCfgBannerUrl") private var cfgBannerUrl: String = ""
    @AppStorage("storeCfgSectionOrder") private var cfgSectionOrder: String = ""
    @AppStorage("storeCfgSectionHidden") private var cfgSectionHidden: String = ""

    private func sectionLabel(_ key: String) -> String {
        switch key {
        case "categories":   return "Danh mục"
        case "products":     return "Sản phẩm"
        case "downloads":    return "Tải về"
        case "contacts":     return "Liên hệ & Cộng đồng"
        case "wishlist":     return "Yêu thích"
        case "recent":       return "Đã xem gần đây"
        case "trust":        return "Thẻ tin cậy (4 ô)"
        case "steps":        return "Thống kê (người dùng · đã bán · đánh giá)"
        case "flash":        return "Flash sale (đếm ngược)"
        case "leaderboard":  return "Bảng xếp hạng nạp"
        case "transactions": return "Giao dịch gần đây"
        case "topups":       return "Nạp tiền gần đây"
        case "gamecat":      return "Danh mục Game (lưới 2 cột)"
        case "announce":     return "Thanh thông báo"
        case "footer":       return "Footer (logo + slogan)"
        default:             return key
        }
    }
    private let allSectionKeys = ["announce", "trust", "steps", "flash", "leaderboard", "categories", "gamecat", "products",
                                  "transactions", "topups", "downloads", "contacts", "wishlist", "recent", "footer"]

    var body: some View {
        Form {
            Section(store.t("Logo cửa hàng", "Store logo")) {
                TextField(store.t("Tên cửa hàng / logo", "Store name / logo"), text: $logoName)
                TextField(store.t("Link ảnh logo (PNG / GIF / JPEG / WEBP)", "Logo image link (PNG / GIF / JPEG / WEBP)"), text: $logoUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            // Ảnh / Video bìa hiển thị to ở đầu cửa hàng (phía sau tên & slogan)
            Section {
                Picker(store.t("Loại bìa", "Cover type"), selection: $bannerType) {
                    Text("Ảnh / GIF").tag("image")
                    Text("Video / MP4").tag("video")
                }.pickerStyle(.segmented)
                TextField(store.t("Dán link ảnh/video bìa (GIF / PNG / JPEG / WEBP / MP4)",
                                  "Paste cover image/video link (GIF / PNG / JPEG / WEBP / MP4)"), text: $bannerUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !bannerUrl.isEmpty {
                    StoreMediaCarousel(media: [StoreMedia(type: bannerType, url: bannerUrl)], height: 120)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            } header: {
                Text(store.t("Ảnh / Video bìa (banner hero)", "Cover image / video (hero banner)"))
            } footer: {
                Text(store.t("Ảnh hoặc video nền hiển thị to ở đầu cửa hàng, phía sau tên & slogan. Hỗ trợ link video URL hoặc PNG / GIF / JPEG / WEBP. Để trống = không hiện bìa.",
                             "Large background image or video at the top of the store, behind the name & slogan. Supports a video URL or PNG / GIF / JPEG / WEBP. Empty = no cover."))
                    .font(.caption2)
            }

            // Dòng giới thiệu (slogan) dưới tên cửa hàng + chọn font đa dạng
            Section(store.t("Dòng giới thiệu (slogan)", "Slogan")) {
                TextField(store.t("Vd: Cửa hàng sản phẩm số · key · tải về", "e.g. Digital store · keys · downloads"), text: $slogan, axis: .vertical)
                    .lineLimit(1...3)
                Picker(store.t("Font chữ", "Font"), selection: $sloganFont) {
                    ForEach(kSloganFonts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Hiệu ứng màu slogan", "Slogan color effect"), selection: $sloganEffect) {
                    ForEach(kLogoEffects, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Chuyển động slogan", "Slogan animation"), selection: $sloganAnim) {
                    ForEach(kLogoAnims, id: \.0) { Text($0.1).tag($0.0) }
                }
                HStack { Spacer()
                    AnimatedStoreText(
                        text: slogan.isEmpty ? store.t("Cửa hàng sản phẩm số · key · tải về", "Digital store · keys · downloads") : slogan,
                        effect: sloganEffect,
                        font: keniosFont(sloganFont, size: 14),
                        anim: sloganAnim)
                    Spacer() }
            }

            // Phần hero (banner chính): tiêu đề lớn + dòng phụ + hiệu ứng
            Section {
                HStack { Spacer()
                    AnimatedStoreText(
                        text: heroTitle.isEmpty ? store.t("GAME CHẤT LƯỢNG CAO · GIÁ TỐT NHẤT", "TOP QUALITY · BEST PRICE") : heroTitle,
                        effect: heroEffect,
                        font: keniosFont(heroFont, size: 17),
                        anim: heroAnim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer() }
                TextField(store.t("Tiêu đề lớn (bỏ trống = dùng slogan)", "Hero title (blank = use slogan)"), text: $heroTitle, axis: .vertical)
                    .lineLimit(1...3)
                TextField(store.t("Dòng phụ (bỏ trống = mặc định)", "Subtitle (blank = default)"), text: $heroSubtitle, axis: .vertical)
                    .lineLimit(1...3)
                Picker(store.t("Hiệu ứng màu tiêu đề", "Title color effect"), selection: $heroEffect) {
                    ForEach(kLogoEffects, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Font tiêu đề", "Title font"), selection: $heroFont) {
                    ForEach(kSloganFonts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Chuyển động tiêu đề", "Title animation"), selection: $heroAnim) {
                    ForEach(kLogoAnims, id: \.0) { Text($0.1).tag($0.0) }
                }
            } header: {
                Text(store.t("Phần hero (banner chính)", "Hero section (main banner)"))
            } footer: {
                Text(store.t("Tiêu đề lớn và dòng phụ trong banner đầu trang. Hỗ trợ 7 màu liên tục, gradient và hiệu ứng động.",
                             "Large title and subtitle in the top hero banner. Supports 7-color rainbow, gradient, and animations."))
                    .font(.caption2)
            }

            // Kích cỡ thẻ sản phẩm / danh mục ngoài trang — KÉO để chỉnh mượt
            Section(store.t("Kích cỡ thẻ hiển thị", "Card display size")) {
                // Nút nhanh
                Picker(store.t("Kích cỡ nhanh", "Quick size"), selection: $cardSize) {
                    Text(store.t("Nhỏ", "Small")).tag("small")
                    Text(store.t("Vừa", "Medium")).tag("medium")
                    Text(store.t("Lớn", "Large")).tag("large")
                }
                .pickerStyle(.segmented)
                .onChange(of: cardSize) { v in
                    cardScale = (v == "small") ? 0.8 : (v == "large" ? 1.25 : 1.0)
                }

                // Thanh kéo tinh chỉnh
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(store.t("Kéo chỉnh kích cỡ", "Drag to resize")).font(.subheadline)
                        Spacer()
                        Text("\(Int(cardScale * 100))%")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(store.accentColor)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.compress.vertical").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $cardScale, in: 0.6...1.6, step: 0.05)
                        Image(systemName: "rectangle.expand.vertical").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                // Xem trước thẻ theo kích cỡ đang chọn
                HStack { Spacer()
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                            .frame(width: 124 * cardScale, height: 84 * cardScale)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        Text(store.t("Xem trước", "Preview")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    Spacer() }
                .padding(.vertical, 4)

                Text(store.t("Kéo sang trái = thẻ nhỏ (nhiều thẻ/hàng), kéo sang phải = thẻ to. Áp cho thẻ danh mục & sản phẩm ngoài trang.",
                             "Drag left = smaller cards (more per row), right = bigger. Applies to category & product cards on the storefront."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Sắp xếp thứ tự + ẩn/hiện các mục hiển thị ngoài trang cửa hàng
            Section {
                ForEach(sections, id: \.self) { key in
                    let hidden = hiddenSections.contains(key)
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Text(sectionLabel(key))
                            .foregroundStyle(hidden ? .secondary : .primary)
                            .strikethrough(hidden)
                        Spacer()
                        Button {
                            if hidden { hiddenSections.remove(key) } else { hiddenSections.insert(key) }
                        } label: {
                            Image(systemName: hidden ? "eye.slash" : "eye")
                                .foregroundStyle(hidden ? .secondary : store.accentColor)
                        }.buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in sections.move(fromOffsets: from, toOffset: to) }
            } header: {
                HStack {
                    Text(store.t("Sắp xếp & ẩn/hiện bố cục", "Arrange & show/hide layout"))
                    Spacer()
                    EditButton().font(.caption)
                }
            } footer: {
                Text(store.t("Kéo ☰ để đổi vị trí; bấm 👁 để ẩn/hiện từng mục cho gọn. Thứ tự & ẩn/hiện áp dụng cho trang khách thấy.",
                             "Drag ☰ to reorder; tap 👁 to show/hide each section. Order & visibility apply to the customer storefront."))
                    .font(.caption2)
            }

            Section(store.t("Hiệu ứng tên/logo cửa hàng", "Store name/logo effects")) {
                HStack { Spacer()
                    AnimatedStoreLogo(text: logoName.isEmpty ? "KENIOS STORE" : logoName,
                                      effect: logoEffect, fontStyle: logoFont, anim: logoAnim, size: 28)
                    Spacer() }
                Picker(store.t("Hiệu ứng màu", "Color effect"), selection: $logoEffect) {
                    ForEach(kLogoEffects, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Kiểu chữ (font)", "Font style"), selection: $logoFont) {
                    ForEach(kLogoFonts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(store.t("Chuyển động", "Animation"), selection: $logoAnim) {
                    ForEach(kLogoAnims, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section(store.t("Nền cửa hàng (full màn hình)", "Store background (full screen)")) {
                Picker(store.t("Loại nền", "Background type"), selection: $bgType) {
                    Text(store.t("Không", "None")).tag("none")
                    Text("Ảnh / GIF").tag("image")
                    Text("Video / MP4").tag("video")
                }.pickerStyle(.segmented)
                if bgType != "none" {
                    TextField(store.t("Dán link nền (GIF / PNG / JPEG / WEBP / MP4)", "Paste background link (GIF / PNG / JPEG / WEBP / MP4)"), text: $bgUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text(store.t("Nền chạy sâu phía dưới, mọi nội dung/nút vẫn nằm bên trên và bấm được.",
                             "The background sits behind; all content/buttons stay on top and remain tappable."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section {
                Toggle(store.t("Bật Flash sale (đếm ngược)", "Enable Flash sale (countdown)"), isOn: $flashEnabled)
                if flashEnabled {
                    TextField(store.t("Tiêu đề (vd FLASH SALE)", "Title (e.g. FLASH SALE)"), text: $flashTitle)
                    HStack {
                        Text(store.t("ID sản phẩm flash", "Flash product ID"))
                        Spacer()
                        TextField("0", value: $flashProductId, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    Stepper(store.t("Giảm giá", "Discount") + ": \(flashDiscount)%", value: $flashDiscount, in: 0...99, step: 1)
                    DatePicker(store.t("Kết thúc lúc", "Ends at"), selection: $flashEnd, in: Date()...)
                }
            } header: {
                Text(store.t("Flash sale", "Flash sale"))
            } footer: {
                Text(store.t("Nhập ID sản phẩm muốn flash (xem ID trong phần quản lý sản phẩm). Hết thời gian sẽ tự ẩn.",
                             "Enter the product ID to feature (see ID in product management). Auto-hides when the countdown ends."))
                    .font(.caption2)
            }

            Section {
                TextField(store.t("Link ảnh khuyến mãi (PNG/GIF/JPEG)", "Promo image link (PNG/GIF/JPEG)"), text: $promoImageUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Text(store.t("ID sản phẩm liên kết", "Linked product ID"))
                    Spacer()
                    TextField("0", value: $promoProductId, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                if !promoImageUrl.isEmpty, let url = URL(string: promoImageUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFit() }
                        else if case .failure = phase { Color(.tertiarySystemBackground) }
                        else { ProgressView() }
                    }
                    .frame(maxHeight: 100).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } header: {
                Text(store.t("Khuyến mãi (ảnh trong ví)", "Promo banner (shown in wallet)"))
            } footer: {
                Text(store.t("Ảnh này hiển thị trong phần Ví, liên kết đến sản phẩm khi bấm vào.",
                             "This image appears in the Wallet section and links to the product when tapped."))
                    .font(.caption2)
            }

            // 3 ô thống kê: Người dùng · Đã bán · Đánh giá (số ẢO + số THẬT tự cộng)
            Section {
                HStack {
                    Label(store.t("Người dùng (ảo)", "Users (virtual)"), systemImage: "person.2.fill")
                    Spacer()
                    TextField("0", value: $statUsersBase, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                }
                HStack {
                    Label(store.t("Đã bán (ảo)", "Sold (virtual)"), systemImage: "bag.fill")
                    Spacer()
                    TextField("0", value: $statSoldBase, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                }
                HStack {
                    Label(store.t("Đánh giá (ảo)", "Reviews (virtual)"), systemImage: "star.fill")
                    Spacer()
                    TextField("0", value: $statReviewsBase, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                }
            } header: {
                Text(store.t("Thống kê cửa hàng", "Store stats"))
            } footer: {
                Text(store.t("3 ô hiển thị đầu trang. Số bạn nhập là số ẢO ban đầu; hệ thống TỰ CỘNG số thật (người dùng đăng ký, sản phẩm đã bán, lượt đánh giá) vào đó.",
                             "Three cards at the top. The number you enter is a virtual base; the system auto-adds the real counts (registered users, items sold, reviews) on top."))
                    .font(.caption2)
            }

            // Thanh thông báo chạy đầu trang
            Section {
                Toggle(store.t("Bật thanh thông báo", "Enable announcement bar"), isOn: $announceEnabled)
                if announceEnabled {
                    TextField(store.t("Nội dung thông báo (vd: Khuyến mãi cuối tuần -20%!)", "Announcement text (e.g. Weekend sale -20%!)"),
                              text: $announceText, axis: .vertical).lineLimit(1...3)
                    Picker(store.t("Màu", "Color"), selection: $announceColor) {
                        Text(store.t("Chủ đạo", "Accent")).tag("accent")
                        Text(store.t("Đỏ", "Red")).tag("red")
                        Text(store.t("Xanh lá", "Green")).tag("green")
                        Text(store.t("Vàng", "Gold")).tag("gold")
                        Text(store.t("Tím", "Purple")).tag("purple")
                    }
                }
            } header: {
                Text(store.t("Thanh thông báo", "Announcement bar"))
            } footer: {
                Text(store.t("Dòng thông báo nổi bật ở đầu trang cửa hàng (vd khuyến mãi, lịch nghỉ...).",
                             "A highlighted notice at the top of the storefront (e.g. promotions, holiday notice)."))
                    .font(.caption2)
            }

            // Số sản phẩm hiển thị mỗi danh mục
            Section {
                Stepper(store.t("Số sản phẩm mỗi danh mục", "Products per category") + ": \(gamecatLimit)",
                        value: $gamecatLimit, in: 2...20, step: 1)
            } footer: {
                Text(store.t("Số sản phẩm tối đa hiện trong lưới mỗi danh mục ở mục \"Danh mục Game\" (bấm \"Xem thêm\" để xem hết).",
                             "Max products shown per category in the \"Game categories\" grid (tap \"See all\" for the rest)."))
                    .font(.caption2)
            }

            Section { Button(store.t("Lưu giao diện", "Save appearance")) { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(store.t("Giao diện cửa hàng", "Store appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        // Hiện ngay giá trị đã lưu (cache) để không bị trống/khôi phục mặc định khi mạng chậm
        logoName = cfgName; logoUrl = cfgLogo; bannerType = cfgBannerType; bannerUrl = cfgBannerUrl
        if let c = try? await store.api.storeConfig() {
            logoName = c.logoName; logoUrl = c.logoUrl
            bannerType = c.bannerType; bannerUrl = c.bannerUrl
            logoEffect = c.logoEffect ?? "rainbow"; logoFont = c.logoFont ?? "rounded"
            logoAnim = c.logoAnim ?? "shimmer"
            bgType = c.bgType ?? "none"; bgUrl = c.bgUrl ?? ""
            slogan = c.slogan ?? ""; sloganFont = c.sloganFont ?? "rounded"
            cardSize = c.cardSize ?? "medium"
            cardScale = Double(c.cardScale ?? "") ?? ((cardSize == "small") ? 0.8 : (cardSize == "large" ? 1.25 : 1.0))
            if let order = c.sectionOrder, !order.isEmpty {
                let parts = order.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                let all = allSectionKeys
                // Giữ các mục hợp lệ theo thứ tự lưu, chèn mục mới còn thiếu vào đúng vị trí
                var merged = parts.filter { all.contains($0) }
                for (i, k) in all.enumerated() where !merged.contains(k) {
                    merged.insert(k, at: min(i, merged.count))
                }
                sections = merged
            }
            if let hidden = c.sectionHidden {
                hiddenSections = Set(hidden.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            }
            flashEnabled = c.flashEnabled ?? false
            flashProductId = c.flashProductId ?? 0
            flashDiscount = c.flashDiscount ?? 0
            flashTitle = c.flashTitle ?? "FLASH SALE"
            if let end = c.flashEnd, end > 0 { flashEnd = Date(timeIntervalSince1970: TimeInterval(end)) }
            heroTitle = c.heroTitle ?? ""
            heroSubtitle = c.heroSubtitle ?? ""
            heroEffect = c.heroEffect ?? "gradient"
            heroFont = c.heroFont ?? "rounded-bold"
            heroAnim = c.heroAnim ?? "none"
            sloganEffect = c.sloganEffect ?? "none"
            sloganAnim = c.sloganAnim ?? "none"
            promoImageUrl = c.promoImageUrl ?? ""
            promoProductId = c.promoProductId ?? 0
            statUsersBase = c.statUsersBase ?? 0
            statSoldBase = c.statSoldBase ?? 0
            statReviewsBase = c.statReviewsBase ?? 0
            announceEnabled = c.announceEnabled ?? false
            announceText = c.announceText ?? ""
            announceColor = c.announceColor ?? "accent"
            gamecatLimit = c.gamecatLimit ?? 6
        }
    }
    private func save() async {
        message = nil
        do {
            let r = try await store.api.adminStoreSetConfig(
                logoName: logoName, logoUrl: logoUrl,
                bannerType: bannerType, bannerUrl: bannerUrl,
                logoEffect: logoEffect, logoFont: logoFont, logoAnim: logoAnim,
                bgType: bgType, bgUrl: bgUrl,
                slogan: slogan, sloganFont: sloganFont,
                sectionOrder: sections.joined(separator: ","),
                sectionHidden: hiddenSections.joined(separator: ","),
                cardSize: cardSize, cardScale: cardScale,
                flashEnabled: flashEnabled, flashProductId: flashProductId,
                flashEnd: Int(flashEnd.timeIntervalSince1970), flashDiscount: flashDiscount,
                flashTitle: flashTitle,
                heroTitle: heroTitle, heroSubtitle: heroSubtitle,
                heroEffect: heroEffect, heroFont: heroFont, heroAnim: heroAnim,
                sloganEffect: sloganEffect, sloganAnim: sloganAnim,
                promoImageUrl: promoImageUrl.isEmpty ? nil : promoImageUrl,
                promoProductId: promoProductId > 0 ? promoProductId : nil,
                statUsersBase: statUsersBase, statSoldBase: statSoldBase,
                statReviewsBase: statReviewsBase,
                announceEnabled: announceEnabled, announceText: announceText,
                announceColor: announceColor, gamecatLimit: gamecatLimit)
            // Lưu cache ngay để các màn khác giữ tên/logo + thứ tự bố cục mới kể cả khi mạng chậm
            cfgName = logoName; cfgLogo = logoUrl; cfgBannerType = bannerType; cfgBannerUrl = bannerUrl
            cfgSectionOrder = sections.joined(separator: ",")
            cfgSectionHidden = hiddenSections.joined(separator: ",")
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Sửa danh mục ----
struct StoreCategoryEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let category: StoreCategory?
    var onDone: () -> Void
    @State private var name = ""
    @State private var media: [EditMedia] = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Tên danh mục", "Category name")) {
                    TextField(store.t("Ví dụ: Game Mod, Tài khoản, Phần mềm...", "e.g. Modded games, Accounts, Software..."), text: $name)
                }
                MediaEditor(media: $media)
                Section { Button(store.t("Lưu danh mục", "Save category")) { Task { await save() } }.disabled(name.isEmpty) }
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(category == nil ? store.t("Thêm danh mục", "Add category") : store.t("Sửa danh mục", "Edit category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .onAppear {
                if let c = category { name = c.name; media = mediaToEdit(c.media) }
            }
        }
    }
    private func save() async {
        message = nil
        do {
            _ = try await store.api.adminStoreSaveCategory(id: category?.id, name: name,
                                                           media: editMediaToPayload(media))
            onDone(); dismiss()
        } catch { message = error.localizedDescription }
    }
}

// ============================ Thư mục con (admin) ============================
struct StoreAdminFolderList: View {
    @EnvironmentObject var store: AppStore
    let category: StoreCategory
    @State private var folders: [StoreFolder] = []
    @State private var editFolder: StoreFolder?
    @State private var newFolder = false
    @State private var error: String?

    var body: some View {
        List {
            Section(store.t("Thư mục con", "Subfolders") + " (\(folders.count))") {
                Button { newFolder = true } label: {
                    Label(store.t("Thêm thư mục con", "Add subfolder"), systemImage: "plus.circle.fill")
                }
                ForEach(folders) { f in
                    NavigationLink {
                        StoreAdminProductList(folder: f)
                    } label: {
                        HStack(spacing: 10) {
                            if let m = f.media.first, m.type != "video", let url = URL(string: m.url) {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                placeholder: { Color(.tertiarySystemBackground) }
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Theme.gold)
                                    .frame(width: 36, height: 36)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(f.name).font(.subheadline)
                            Spacer()
                            Button { editFolder = f } label: {
                                Image(systemName: "pencil.circle").foregroundStyle(.secondary)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .onDelete { idx in Task { await deleteFolders(idx) } }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $newFolder) {
            StoreFolderEditor(categoryId: category.id, folder: nil) { Task { await reload() } }
        }
        .sheet(item: $editFolder) { f in
            StoreFolderEditor(categoryId: category.id, folder: f) { Task { await reload() } }
        }
    }

    private func reload() async {
        folders = (try? await store.api.storeFolders(categoryId: category.id)) ?? []
    }
    private func deleteFolders(_ idx: IndexSet) async {
        for i in idx { _ = try? await store.api.adminStoreDeleteFolder(folders[i].id) }
        await reload()
    }
}

struct StoreFolderEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let categoryId: Int
    let folder: StoreFolder?
    var onDone: () -> Void
    @State private var name = ""
    @State private var media: [EditMedia] = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Tên thư mục con", "Subfolder name")) {
                    TextField(store.t("Ví dụ: Liên Quân, PUBG, Free Fire...", "e.g. Arena, PUBG, Free Fire..."), text: $name)
                }
                MediaEditor(media: $media)
                Section { Button(store.t("Lưu thư mục", "Save folder")) { Task { await save() } }.disabled(name.isEmpty) }
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(folder == nil ? store.t("Thêm thư mục", "Add folder") : store.t("Sửa thư mục", "Edit folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .onAppear { if let f = folder { name = f.name; media = mediaToEdit(f.media) } }
        }
    }
    private func save() async {
        message = nil
        do {
            _ = try await store.api.adminStoreSaveFolder(id: folder?.id, categoryId: categoryId,
                                                         name: name, media: editMediaToPayload(media))
            onDone(); dismiss()
        } catch { message = error.localizedDescription }
    }
}

// ============================ Sản phẩm (admin) ============================
struct StoreAdminProductList: View {
    @EnvironmentObject var store: AppStore
    let folder: StoreFolder
    @State private var products: [StoreProduct] = []
    @State private var newProduct = false
    @State private var error: String?

    var body: some View {
        List {
            Section(store.t("Sản phẩm", "Products") + " (\(products.count))") {
                Button { newProduct = true } label: {
                    Label(store.t("Thêm sản phẩm", "Add product"), systemImage: "plus.circle.fill")
                }
                ForEach(products) { p in
                    NavigationLink {
                        StoreProductEditor(folderId: folder.id, product: p) { Task { await reload() } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                // ID THẬT của sản phẩm — dùng để điền vào Flash sale / Khuyến mãi
                                Text("#\(String(format: "%02d", p.id))")
                                    .font(.caption.bold().monospacedDigit())
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(store.accentColor.opacity(0.18))
                                    .foregroundStyle(store.accentColor)
                                    .clipShape(Capsule())
                                Text(p.name)
                            }
                            HStack(spacing: 6) {
                                Text("\(p.prices.count) " + store.t("mốc giá", "price tiers"))
                                    .font(.caption2).foregroundStyle(.secondary)
                                stockBadge(p.availableKeys)
                            }
                        }
                    }
                }
                .onDelete { idx in Task { await deleteProducts(idx) } }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $newProduct) {
            StoreProductEditor(folderId: folder.id, product: nil) { Task { await reload() } }
        }
    }

    @ViewBuilder private func stockBadge(_ count: Int) -> some View {
        let label = count == 0 ? "Hết hàng" : count <= 5 ? "Sắp hết (\(count))" : "Còn \(count)"
        let color: Color = count == 0 ? .red : count <= 5 ? .orange : .green
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func reload() async {
        products = (try? await store.api.storeProducts(folderId: folder.id)) ?? []
    }
    private func deleteProducts(_ idx: IndexSet) async {
        for i in idx { _ = try? await store.api.adminStoreDeleteProduct(products[i].id) }
        await reload()
    }
}

struct StoreProductEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let folderId: Int
    let product: StoreProduct?
    var onDone: () -> Void

    @State private var savedId: Int?
    @State private var name = ""
    @State private var desc = ""
    @State private var kind = "app"   // app (key/ứng dụng) | acc (acc game)
    @State private var media: [EditMedia] = []
    @State private var downloadUrl = ""
    @State private var downloadFileId: Int?
    @State private var uploading = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var isError = false

    private var productId: Int? { product?.id ?? savedId }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Thông tin sản phẩm", "Product info")) {
                    if let pid = productId {
                        HStack {
                            Label(store.t("ID sản phẩm", "Product ID"), systemImage: "number")
                            Spacer()
                            Text("#\(String(format: "%02d", pid))")
                                .font(.body.bold().monospacedDigit())
                                .foregroundStyle(store.accentColor)
                            Text("(\(pid))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker(store.t("Loại", "Type"), selection: $kind) {
                        Text(store.t("Ứng dụng / Key", "App / Key")).tag("app")
                        Text(store.t("Acc game", "Game account")).tag("acc")
                    }.pickerStyle(.segmented)
                    TextField(store.t("Tên sản phẩm", "Product name"), text: $name)
                    TextField(store.t("Mô tả (tuỳ chọn)", "Description (optional)"), text: $desc, axis: .vertical).lineLimit(1...4)
                    Text(kind == "acc"
                         ? store.t("Acc game: mỗi dòng trong kho là 1 tài khoản (vd user|pass). Khách mua xong tự nhận 1 acc.", "Game account: each line in stock is 1 account (e.g. user|pass). Buyer auto-receives 1 account.")
                         : store.t("Ứng dụng/Key: mỗi dòng trong kho là 1 key. Khách mua xong tự nhận 1 key + bản tải.", "App/Key: each line in stock is 1 key. Buyer auto-receives 1 key + download."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                MediaEditor(media: $media)
                Section(store.t("Bản tải (link hoặc file)", "Download (link or file)")) {
                    TextField(store.t("Dán link tải game/app", "Paste game/app download link"), text: $downloadUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            if uploading { ProgressView().padding(.trailing, 4) }
                            Label(downloadFileId != nil ? store.t("Đã có file", "File added") + " (#\(downloadFileId!)) — " + store.t("đổi file", "change file")
                                                        : store.t("Tải file lên (không giới hạn dung lượng)", "Upload file (no size limit)"),
                                  systemImage: "arrow.up.doc")
                        }
                    }.disabled(uploading)
                    Text(store.t("Khách mua xong sẽ thấy nút 'Tải game' đồng bộ với link/file ở đây.",
                                 "After buying, customers see a 'Download game' button synced with the link/file here."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button(store.t("Lưu sản phẩm", "Save product")) { Task { await save() } }.disabled(name.isEmpty) }

                if let pid = productId {
                    Section(store.t("Cấu hình bán", "Sale config")) {
                        NavigationLink {
                            StorePricesEditor(productId: pid, initial: product?.prices ?? [], kind: kind)
                        } label: {
                            Label(kind == "acc" ? store.t("Giá bán acc", "Account price") : store.t("Bảng giá theo thời hạn", "Price table by duration"),
                                  systemImage: "tag")
                        }
                        NavigationLink {
                            StoreKeysManager(productId: pid)
                        } label: {
                            Label(kind == "acc" ? store.t("Kho tài khoản (ACC)", "Account stock (ACC)") : store.t("Kho KEY sản phẩm", "Product KEY stock"),
                                  systemImage: kind == "acc" ? "person.text.rectangle" : "key")
                        }
                    }
                } else {
                    Text(store.t("Lưu sản phẩm trước để thêm giá & key/tài khoản.", "Save the product first to add prices & keys/accounts."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
            }
            .navigationTitle(product == nil ? store.t("Thêm sản phẩm", "Add product") : store.t("Sửa sản phẩm", "Edit product"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .onAppear {
                if let p = product {
                    name = p.name; desc = p.description; media = mediaToEdit(p.media)
                    kind = p.kind ?? "app"
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(allowsMultipleSelection: false) { urls in
                    if let url = urls.first { Task { await uploadFile(url) } }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func save() async {
        message = nil
        do {
            let isNew = product == nil
            let r = try await store.api.adminStoreSaveProduct(
                id: productId, folderId: folderId, name: name, description: desc,
                media: editMediaToPayload(media), downloadUrl: downloadUrl,
                downloadFileId: downloadFileId, kind: kind)
            savedId = r.id ?? savedId
            isError = false; message = store.t("Đã lưu sản phẩm.", "Product saved.")
            // Thông báo đến người dùng khi có sản phẩm mới (không phải chỉnh sửa)
            if isNew {
                store.postProductNotification(
                    body: store.t("Sản phẩm mới vừa được thêm vào cửa hàng:", "A new product was added to the store:") + " \(name)")
            }
            onDone()
        } catch { isError = true; message = error.localizedDescription }
    }

    private func uploadFile(_ url: URL) async {
        uploading = true; message = nil
        let access = url.startAccessingSecurityScopedResource()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        do { try FileManager.default.copyItem(at: url, to: tmp) } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            isError = true; message = store.t("Không đọc được file.", "Could not read file.")
            uploading = false; return
        }
        if access { url.stopAccessingSecurityScopedResource() }
        do {
            let r = try await store.api.uploadFileRaw(name: url.lastPathComponent,
                                                      category: "store", fileURL: tmp)
            downloadFileId = r.id
            isError = false; message = store.t("Đã tải file lên", "File uploaded") + " (#\(r.id)). " + store.t("Nhớ bấm Lưu sản phẩm.", "Remember to tap Save product.")
        } catch { isError = true; message = error.localizedDescription }
        uploading = false
        try? FileManager.default.removeItem(at: tmp)
    }
}

// ============================ Thêm sản phẩm — TẤT CẢ TRONG 1 ============================
// Một màn duy nhất: chọn/tạo Danh mục → chọn/tạo Thư mục con → nhập Sản phẩm
// (ảnh/video, bản tải) → đặt Giá theo thời hạn → nhập Key cho TỪNG mốc.
// Bắt buộc phải chọn (tích) danh mục & thư mục con trước mới thêm được sản phẩm.
struct QuickPriceRow: Identifiable, Hashable {
    let id = UUID()
    var label: String = ""
    var amount: String = ""
    var keys: String = ""      // key nhập riêng cho mốc này (mỗi dòng 1 key)
}

struct StoreQuickAddView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var onDone: () -> Void

    // Dữ liệu
    @State private var categories: [StoreCategory] = []
    @State private var folders: [StoreFolder] = []
    @State private var existingProducts: [StoreProduct] = []

    // Lựa chọn
    @State private var selectedCategoryId: Int?
    @State private var selectedFolderId: Int?

    // Đổi tên inline danh mục / thư mục con
    @State private var editCatId: Int?
    @State private var editCatNameText = ""
    @State private var editFldId: Int?
    @State private var editFldNameText = ""

    // Quản lý sản phẩm hiện có
    @State private var expandedProductId: Int?
    @State private var editProductNames: [Int: String] = [:]
    @State private var editProductDownloadUrls: [Int: String] = [:]
    @State private var editProductDownloadFileIds: [Int: Int] = [:]
    @State private var uploadingDownloadFor: Int?
    @State private var showDownloadPickerFor: Int?
    @State private var keysData: [Int: StoreKeysInfo] = [:]
    @State private var addKeysText: [Int: String] = [:]
    @State private var addingKeysFor: Int?
    @State private var deletingKeyId: Int?
    @State private var savingProductId: Int?

    // Tạo danh mục mới
    @State private var showNewCat = false
    @State private var newCatName = ""
    @State private var newCatMedia: [EditMedia] = []
    @State private var savingCat = false

    // Tạo thư mục con mới
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderMedia: [EditMedia] = []
    @State private var savingFolder = false

    // Sản phẩm mới
    @State private var kind = "app"
    @State private var name = ""
    @State private var desc = ""
    @State private var media: [EditMedia] = []
    @State private var downloadUrl = ""
    @State private var downloadFileId: Int?
    @State private var uploading = false
    @State private var showImporter = false

    // Giá + key
    @State private var priceRows: [QuickPriceRow] = [QuickPriceRow()]
    @State private var accPrice = ""
    @State private var accKeys = ""

    // Trạng thái
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    private let presets = ["1 giờ", "1 ngày", "1 tuần", "1 tháng", "Vĩnh viễn"]
    private var hasCategory: Bool { selectedCategoryId != nil }
    private var hasFolder: Bool { selectedFolderId != nil }
    private var isAcc: Bool { kind == "acc" }

    var body: some View {
        NavigationStack {
            Form {
                // ---------- BƯỚC 1: DANH MỤC ----------
                Section {
                    if categories.isEmpty {
                        Text(store.t("Chưa có danh mục — hãy tạo mới bên dưới.", "No categories yet — create one below."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(categories) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 0) {
                                Button {
                                    selectedCategoryId = c.id
                                    selectedFolderId = nil
                                    editCatId = nil
                                    Task { await loadFolders() }
                                } label: {
                                    pickRow(thumb: c.media.first, title: c.name, selected: selectedCategoryId == c.id)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    if editCatId == c.id { editCatId = nil }
                                    else { editCatId = c.id; editCatNameText = c.name }
                                } label: {
                                    Image(systemName: editCatId == c.id ? "xmark.circle" : "pencil.circle")
                                        .foregroundStyle(editCatId == c.id ? .secondary : Theme.accent)
                                        .font(.title3)
                                        .padding(.leading, 8)
                                }
                                .buttonStyle(.borderless)
                            }
                            if editCatId == c.id {
                                HStack {
                                    TextField(store.t("Tên danh mục", "Category name"), text: $editCatNameText)
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        Task { await renameCategory(c) }
                                    } label: {
                                        Text(store.t("Lưu", "Save")).font(.caption.bold())
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Theme.accent).foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(editCatNameText.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                    }
                    Button { withAnimation { showNewCat.toggle() } } label: {
                        Label(showNewCat ? store.t("Ẩn tạo danh mục", "Hide create category") : store.t("Tạo danh mục mới", "Create new category"),
                              systemImage: showNewCat ? "minus.circle" : "plus.circle.fill")
                    }
                    if showNewCat {
                        TextField(store.t("Tên danh mục mới", "New category name"), text: $newCatName)
                        Button {
                            Task { await createCategory() }
                        } label: {
                            HStack { if savingCat { ProgressView().padding(.trailing, 4) }
                                Text(store.t("Lưu danh mục", "Save category")) }
                        }.disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty || savingCat)
                    }
                } header: {
                    Label(store.t("Bước 1 · Chọn / tạo danh mục", "Step 1 · Pick / create category"), systemImage: "1.circle.fill")
                }
                if showNewCat { MediaEditor(media: $newCatMedia) }

                // ---------- BƯỚC 2: THƯ MỤC CON ----------
                Section {
                    if !hasCategory {
                        Text(store.t("Hãy chọn hoặc tạo danh mục ở Bước 1 trước.", "Pick or create a category in Step 1 first."))
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        if folders.isEmpty {
                            Text(store.t("Danh mục này chưa có thư mục con — hãy tạo mới.", "This category has no subfolders — create one."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(folders) { f in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 0) {
                                    Button {
                                        selectedFolderId = f.id
                                        editFldId = nil
                                        Task { await loadProducts() }
                                    } label: {
                                        pickRow(thumb: f.media.first, title: f.name, selected: selectedFolderId == f.id)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        if editFldId == f.id { editFldId = nil }
                                        else { editFldId = f.id; editFldNameText = f.name }
                                    } label: {
                                        Image(systemName: editFldId == f.id ? "xmark.circle" : "pencil.circle")
                                            .foregroundStyle(editFldId == f.id ? .secondary : Theme.accent)
                                            .font(.title3)
                                            .padding(.leading, 8)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if editFldId == f.id {
                                    HStack {
                                        TextField(store.t("Tên thư mục con", "Subfolder name"), text: $editFldNameText)
                                            .textFieldStyle(.roundedBorder)
                                        Button {
                                            Task { await renameFolder(f) }
                                        } label: {
                                            Text(store.t("Lưu", "Save")).font(.caption.bold())
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(Theme.accent).foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(editFldNameText.trimmingCharacters(in: .whitespaces).isEmpty)
                                    }
                                }
                            }
                        }
                        Button { withAnimation { showNewFolder.toggle() } } label: {
                            Label(showNewFolder ? store.t("Ẩn tạo thư mục con", "Hide create subfolder") : store.t("Tạo thư mục con mới", "Create new subfolder"),
                                  systemImage: showNewFolder ? "minus.circle" : "plus.circle.fill")
                        }
                        if showNewFolder {
                            TextField(store.t("Tên thư mục con mới", "New subfolder name"), text: $newFolderName)
                            Button {
                                Task { await createFolder() }
                            } label: {
                                HStack { if savingFolder { ProgressView().padding(.trailing, 4) }
                                    Text(store.t("Lưu thư mục con", "Save subfolder")) }
                            }.disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || savingFolder)
                        }
                    }
                } header: {
                    Label(store.t("Bước 2 · Chọn / tạo thư mục con", "Step 2 · Pick / create subfolder"), systemImage: "2.circle.fill")
                }
                if showNewFolder && hasCategory { MediaEditor(media: $newFolderMedia) }

                // ---------- SẢN PHẨM HIỆN CÓ (quản lý / sửa / key) ----------
                if hasFolder && !existingProducts.isEmpty {
                    Section {
                        ForEach(existingProducts) { p in
                            VStack(alignment: .leading, spacing: 0) {
                                // Header row – bấm để mở/đóng
                                Button {
                                    withAnimation {
                                        if expandedProductId == p.id {
                                            expandedProductId = nil
                                        } else {
                                            expandedProductId = p.id
                                            if editProductNames[p.id] == nil { editProductNames[p.id] = p.name }
                                            if keysData[p.id] == nil { Task { await loadKeysForProduct(p.id) } }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                                            Text(p.prices.map { kFormatVND($0.amount) }.joined(separator: " · "))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: expandedProductId == p.id ? "chevron.up" : "chevron.down")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if expandedProductId == p.id {
                                    Divider().padding(.vertical, 8)

                                    // Đổi tên sản phẩm
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(store.t("Tên sản phẩm", "Product name")).font(.caption).foregroundStyle(.secondary)
                                        HStack {
                                            TextField(store.t("Tên sản phẩm", "Product name"),
                                                      text: Binding(
                                                        get: { editProductNames[p.id] ?? p.name },
                                                        set: { editProductNames[p.id] = $0 }))
                                                .textFieldStyle(.roundedBorder)
                                            if savingProductId == p.id {
                                                ProgressView()
                                            } else {
                                                Button {
                                                    Task { await saveProductName(p) }
                                                } label: {
                                                    Text(store.t("Lưu", "Save")).font(.caption.bold())
                                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                                        .background(Theme.accent).foregroundStyle(.white)
                                                        .clipShape(Capsule())
                                                }
                                                .buttonStyle(.borderless)
                                            }
                                        }
                                    }
                                    .padding(.bottom, 10)

                                    // Link tải / File
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(store.t("Link tải / File", "Download link / File"))
                                            .font(.caption).foregroundStyle(.secondary)
                                        HStack {
                                            TextField(store.t("Dán link tải mới...", "Paste new download link..."),
                                                      text: Binding(
                                                        get: { editProductDownloadUrls[p.id] ?? "" },
                                                        set: { editProductDownloadUrls[p.id] = $0 }))
                                                .textFieldStyle(.roundedBorder)
                                                .autocorrectionDisabled()
                                                .textInputAutocapitalization(.never)
                                                .font(.caption)
                                            Button {
                                                Task { await saveProductDownload(p) }
                                            } label: {
                                                Text(store.t("Lưu", "Save")).font(.caption.bold())
                                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                                    .background(Theme.accent).foregroundStyle(.white)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(savingProductId == p.id || uploadingDownloadFor == p.id)
                                        }
                                        Button {
                                            showDownloadPickerFor = p.id
                                        } label: {
                                            HStack(spacing: 4) {
                                                if uploadingDownloadFor == p.id {
                                                    ProgressView().scaleEffect(0.7)
                                                } else {
                                                    Image(systemName: "arrow.up.doc")
                                                }
                                                if let fid = editProductDownloadFileIds[p.id] {
                                                    Text(store.t("Đổi file", "Change file") + " (#\(fid))")
                                                } else {
                                                    Text(store.t("Tải file mới lên", "Upload new file"))
                                                }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(Theme.accent)
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(uploadingDownloadFor != nil)
                                    }
                                    .padding(.bottom, 10)

                                    // Giá hiện có
                                    if !p.prices.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(store.t("Mốc giá", "Price tiers")).font(.caption).foregroundStyle(.secondary)
                                            ForEach(p.prices) { pr in
                                                HStack {
                                                    Text(pr.label).font(.caption)
                                                    Spacer()
                                                    Text(kFormatVND(pr.amount)).font(.caption.bold()).foregroundStyle(Theme.accent)
                                                    Text("(\(pr.available ?? 0) key)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .padding(.bottom, 10)
                                    }

                                    // KEY: danh sách hiện có + xóa từng key
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(store.t("Kho key", "Key stock")).font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            if let info = keysData[p.id] {
                                                Text("\(info.available)/\(info.total)").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        if let info = keysData[p.id] {
                                            let avail = info.keys.filter { $0.status == "available" }
                                            if avail.isEmpty {
                                                Text(store.t("Không có key nào.", "No keys available."))
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            } else {
                                                ForEach(avail.prefix(30)) { k in
                                                    HStack {
                                                        Text(k.keyText)
                                                            .font(.system(.caption2, design: .monospaced))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        Spacer()
                                                        if deletingKeyId == k.id {
                                                            ProgressView().scaleEffect(0.7)
                                                        } else {
                                                            Button {
                                                                Task { await deleteKey(k.id, productId: p.id) }
                                                            } label: {
                                                                Image(systemName: "trash")
                                                                    .font(.caption).foregroundStyle(.red)
                                                            }
                                                            .buttonStyle(.borderless)
                                                        }
                                                    }
                                                }
                                                if avail.count > 30 {
                                                    Text("+ \(avail.count - 30) " + store.t("key khác", "more keys"))
                                                        .font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        } else {
                                            ProgressView()
                                        }

                                        // Thêm key mới
                                        DisclosureGroup(
                                            isExpanded: Binding(
                                                get: { addingKeysFor == p.id },
                                                set: { addingKeysFor = $0 ? p.id : nil }),
                                            content: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    TextEditor(text: Binding(
                                                        get: { addKeysText[p.id] ?? "" },
                                                        set: { addKeysText[p.id] = $0 }))
                                                        .frame(minHeight: 80)
                                                        .font(.system(.caption, design: .monospaced))
                                                    Text(store.t("Mỗi dòng 1 key. Bấm Lưu để thêm vào kho.",
                                                                 "One key per line. Tap Save to add to stock."))
                                                        .font(.caption2).foregroundStyle(.secondary)
                                                    Button {
                                                        Task { await addKeysToProduct(p.id) }
                                                    } label: {
                                                        Label(store.t("Lưu key", "Save keys"), systemImage: "key.fill")
                                                            .font(.caption.bold())
                                                            .frame(maxWidth: .infinity).frame(height: 36)
                                                            .background(Theme.accent).foregroundStyle(.white)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    }
                                                    .buttonStyle(.plain)
                                                    .disabled((addKeysText[p.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                                }
                                            },
                                            label: {
                                                Label(store.t("Thêm key mới", "Add new keys"), systemImage: "plus.circle")
                                                    .font(.caption)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Label(store.t("Sản phẩm trong thư mục", "Products in folder") + " (\(existingProducts.count))", systemImage: "cube.box.fill")
                            Spacer()
                            Button { Task { await loadProducts() } } label: {
                                Image(systemName: "arrow.clockwise").font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }

                // ---------- BƯỚC 3: SẢN PHẨM ----------
                if hasFolder {
                    Section {
                        Picker(store.t("Loại", "Type"), selection: $kind) {
                            Text(store.t("Ứng dụng / Key", "App / Key")).tag("app")
                            Text(store.t("Acc game", "Game account")).tag("acc")
                        }.pickerStyle(.segmented)
                        TextField(store.t("Tên sản phẩm", "Product name"), text: $name)
                        TextField(store.t("Mô tả (tuỳ chọn)", "Description (optional)"), text: $desc, axis: .vertical).lineLimit(1...4)
                    } header: {
                        Label(store.t("Bước 3 · Thông tin sản phẩm", "Step 3 · Product info"), systemImage: "3.circle.fill")
                    }
                    MediaEditor(media: $media)
                    Section(store.t("Bản tải (link hoặc file)", "Download (link or file)")) {
                        TextField(store.t("Dán link tải game/app", "Paste game/app download link"), text: $downloadUrl)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { showImporter = true } label: {
                            HStack { if uploading { ProgressView().padding(.trailing, 4) }
                                Label(downloadFileId != nil ? store.t("Đã có file", "File added") + " (#\(downloadFileId!)) — " + store.t("đổi file", "change file")
                                                            : store.t("Tải file lên (không giới hạn dung lượng)", "Upload file (no size limit)"),
                                      systemImage: "arrow.up.doc") }
                        }.disabled(uploading)
                    }

                    // ---------- BƯỚC 4: GIÁ + KEY ----------
                    if isAcc {
                        Section {
                            HStack {
                                TextField(store.t("Giá VND", "Price VND"), text: $accPrice).keyboardType(.numberPad)
                                Text("đ").foregroundStyle(.secondary)
                            }
                            TextEditor(text: $accKeys).frame(minHeight: 100)
                            Text(store.t("Mỗi dòng 1 tài khoản (vd user|pass). Khách mua nhận ngay 1 acc.",
                                         "One account per line (e.g. user|pass). Buyer instantly receives 1 account."))
                                .font(.caption2).foregroundStyle(.secondary)
                        } header: {
                            Label(store.t("Bước 4 · Giá & kho acc", "Step 4 · Price & account stock"), systemImage: "4.circle.fill")
                        }
                    } else {
                        Section {
                            ForEach($priceRows) { $r in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TextField(store.t("Thời hạn (vd 1 ngày)", "Duration (e.g. 1 day)"), text: $r.label)
                                        TextField(store.t("Giá VND", "Price VND"), text: $r.amount).keyboardType(.numberPad)
                                            .frame(width: 100)
                                    }
                                    DisclosureGroup {
                                        TextEditor(text: $r.keys).frame(minHeight: 90)
                                        Text(store.t("Mỗi dòng 1 key — chỉ dùng cho mốc này.", "One key per line — only for this tier."))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    } label: {
                                        Label(store.t("Nhập key cho mốc này", "Add keys for this tier"), systemImage: "key")
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete { priceRows.remove(atOffsets: $0) }
                            Button { priceRows.append(QuickPriceRow()) } label: {
                                Label(store.t("Thêm mốc giá", "Add price tier"), systemImage: "plus.circle")
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(presets, id: \.self) { p in
                                        Button(p) { priceRows.append(QuickPriceRow(label: p)) }
                                            .font(.caption)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        } header: {
                            Label(store.t("Bước 4 · Giá theo thời hạn + nhập key", "Step 4 · Prices by duration + keys"), systemImage: "4.circle.fill")
                        } footer: {
                            Text(store.t("Mỗi mốc có kho key RIÊNG. Mở 'Nhập key cho mốc này' để dán key cho từng mốc. Hết mốc nào → mốc đó hiện 'Hết hàng'.",
                                         "Each tier has its OWN key stock. Open 'Add keys for this tier' to paste keys per tier. When a tier runs out it shows 'Out of stock'."))
                                .font(.caption2)
                        }
                    }

                    Section {
                        Button {
                            Task { await saveAll() }
                        } label: {
                            HStack { if saving { ProgressView().padding(.trailing, 4) }
                                Text(store.t("Lưu tất cả (tạo sản phẩm + giá + key)", "Save all (create product + prices + keys)")).bold() }
                        }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    }
                } else {
                    Section {
                        Text(store.t("Hãy chọn hoặc tạo thư mục con ở Bước 2 trước khi thêm sản phẩm.",
                                     "Pick or create a subfolder in Step 2 before adding a product."))
                            .font(.caption).foregroundStyle(.orange)
                    } header: {
                        Label(store.t("Bước 3 · Sản phẩm", "Step 3 · Product"), systemImage: "3.circle")
                    }
                }

                if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
            }
            .navigationTitle(store.t("Thêm sản phẩm (tất cả trong 1)", "Add product (all-in-one)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await loadCategories() }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(allowsMultipleSelection: false) { urls in
                    if let url = urls.first { Task { await uploadFile(url) } }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { showDownloadPickerFor != nil },
                set: { if !$0 { showDownloadPickerFor = nil } }
            )) {
                if let pid = showDownloadPickerFor {
                    DocumentPicker(allowsMultipleSelection: false) { urls in
                        showDownloadPickerFor = nil
                        if let url = urls.first { Task { await uploadDownloadFile(url, productId: pid) } }
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    // Hàng chọn — cuộn đến và bấm để chọn (không có icon tích)
    @ViewBuilder private func pickRow(thumb: StoreMedia?, title: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let m = thumb, m.type != "video", let url = URL(string: m.url) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { Color(.tertiarySystemBackground) }
                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "folder.fill")
                    .foregroundStyle(selected ? store.accentColor : Theme.gold)
                    .frame(width: 34, height: 34)
                    .background(selected ? store.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Text(title)
                .foregroundStyle(selected ? store.accentColor : .primary)
                .fontWeight(selected ? .semibold : .regular)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .background(selected ? store.accentColor.opacity(0.07) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // ---- Tải dữ liệu ----
    private func loadCategories() async {
        categories = (try? await store.api.storeCategories()) ?? []
    }
    private func loadFolders() async {
        guard let cid = selectedCategoryId else { folders = []; return }
        folders = (try? await store.api.storeFolders(categoryId: cid)) ?? []
    }

    // ---- Tạo danh mục / thư mục ----
    private func createCategory() async {
        savingCat = true; message = nil
        do {
            let r = try await store.api.adminStoreSaveCategory(id: nil, name: newCatName,
                                                               media: editMediaToPayload(newCatMedia))
            await loadCategories()
            selectedCategoryId = r.id
            selectedFolderId = nil
            await loadFolders()
            newCatName = ""; newCatMedia = []; withAnimation { showNewCat = false }
            isError = false; message = store.t("Đã tạo danh mục.", "Category created.")
        } catch { isError = true; message = error.localizedDescription }
        savingCat = false
    }
    private func createFolder() async {
        guard let cid = selectedCategoryId else { return }
        savingFolder = true; message = nil
        do {
            let r = try await store.api.adminStoreSaveFolder(id: nil, categoryId: cid, name: newFolderName,
                                                             media: editMediaToPayload(newFolderMedia))
            await loadFolders()
            selectedFolderId = r.id
            newFolderName = ""; newFolderMedia = []; withAnimation { showNewFolder = false }
            isError = false; message = store.t("Đã tạo thư mục con.", "Subfolder created.")
        } catch { isError = true; message = error.localizedDescription }
        savingFolder = false
    }

    // ---- Đổi tên danh mục / thư mục con ----
    private func renameCategory(_ c: StoreCategory) async {
        let newName = editCatNameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        do {
            _ = try await store.api.adminStoreSaveCategory(id: c.id, name: newName, media: editMediaToPayload(mediaToEdit(c.media)))
            await loadCategories()
            editCatId = nil
            isError = false; message = store.t("Đã đổi tên danh mục.", "Category renamed.")
        } catch { isError = true; message = error.localizedDescription }
    }
    private func renameFolder(_ f: StoreFolder) async {
        guard let cid = selectedCategoryId else { return }
        let newName = editFldNameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        do {
            _ = try await store.api.adminStoreSaveFolder(id: f.id, categoryId: cid, name: newName, media: editMediaToPayload(mediaToEdit(f.media)))
            await loadFolders()
            editFldId = nil
            isError = false; message = store.t("Đã đổi tên thư mục.", "Folder renamed.")
        } catch { isError = true; message = error.localizedDescription }
    }

    // ---- Quản lý sản phẩm hiện có ----
    private func loadProducts() async {
        guard let fid = selectedFolderId else { existingProducts = []; return }
        existingProducts = (try? await store.api.storeProducts(folderId: fid)) ?? []
    }
    private func loadKeysForProduct(_ pid: Int) async {
        keysData[pid] = try? await store.api.adminStoreListKeys(productId: pid)
    }
    private func saveProductName(_ p: StoreProduct) async {
        guard let fid = selectedFolderId else { return }
        let newName = (editProductNames[p.id] ?? p.name).trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        savingProductId = p.id
        do {
            _ = try await store.api.adminStoreSaveProduct(
                id: p.id, folderId: fid, name: newName, description: p.description,
                media: editMediaToPayload(mediaToEdit(p.media)),
                downloadUrl: "", downloadFileId: nil, kind: p.kind ?? "app")
            await loadProducts()
            isError = false; message = store.t("Đã cập nhật sản phẩm.", "Product updated.")
        } catch { isError = true; message = error.localizedDescription }
        savingProductId = nil
    }
    private func deleteKey(_ keyId: Int, productId: Int) async {
        deletingKeyId = keyId
        do {
            _ = try await store.api.adminStoreDeleteKey(keyId)
        } catch {
            isError = true; message = error.localizedDescription
        }
        await loadKeysForProduct(productId)
        deletingKeyId = nil
    }
    private func uploadDownloadFile(_ url: URL, productId: Int) async {
        uploadingDownloadFor = productId
        do {
            let r = try await store.api.uploadFileRaw(name: url.lastPathComponent, category: "store", fileURL: url)
            editProductDownloadFileIds[productId] = r.id
            if let p = existingProducts.first(where: { $0.id == productId }) {
                await saveProductDownload(p, fileId: r.id)
            }
        } catch { isError = true; message = error.localizedDescription }
        uploadingDownloadFor = nil
    }
    private func saveProductDownload(_ p: StoreProduct, fileId: Int? = nil) async {
        guard let fid = selectedFolderId else { return }
        let url = (editProductDownloadUrls[p.id] ?? "").trimmingCharacters(in: .whitespaces)
        savingProductId = p.id
        do {
            _ = try await store.api.adminStoreSaveProduct(
                id: p.id, folderId: fid,
                name: editProductNames[p.id] ?? p.name,
                description: p.description,
                media: editMediaToPayload(mediaToEdit(p.media)),
                downloadUrl: url,
                downloadFileId: fileId ?? editProductDownloadFileIds[p.id],
                kind: p.kind ?? "app")
            await loadProducts()
            isError = false; message = store.t("Đã cập nhật link tải.", "Download updated.")
        } catch { isError = true; message = error.localizedDescription }
        savingProductId = nil
    }
    private func addKeysToProduct(_ productId: Int) async {
        let txt = (addKeysText[productId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return }
        let priceId = existingProducts.first(where: { $0.id == productId })?.prices.first?.id
        do {
            _ = try await store.api.adminStoreAddKeys(productId: productId, text: txt, priceId: priceId)
            addKeysText[productId] = ""
            addingKeysFor = nil
            await loadKeysForProduct(productId)
            isError = false; message = store.t("Đã thêm key.", "Keys added.")
        } catch { isError = true; message = error.localizedDescription }
    }

    private func uploadFile(_ url: URL) async {
        uploading = true; message = nil
        let access = url.startAccessingSecurityScopedResource()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        do { try FileManager.default.copyItem(at: url, to: tmp) } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            isError = true; message = store.t("Không đọc được file.", "Could not read file.")
            uploading = false; return
        }
        if access { url.stopAccessingSecurityScopedResource() }
        do {
            let r = try await store.api.uploadFileRaw(name: url.lastPathComponent, category: "store", fileURL: tmp)
            downloadFileId = r.id
            isError = false; message = store.t("Đã tải file lên", "File uploaded") + " (#\(r.id))."
        } catch { isError = true; message = error.localizedDescription }
        uploading = false
        try? FileManager.default.removeItem(at: tmp)
    }

    // ---- Lưu tất cả ----
    private func saveAll() async {
        guard let fid = selectedFolderId else { return }
        saving = true; message = nil
        do {
            // 1) Tạo sản phẩm
            let prod = try await store.api.adminStoreSaveProduct(
                id: nil, folderId: fid, name: name, description: desc,
                media: editMediaToPayload(media), downloadUrl: downloadUrl,
                downloadFileId: downloadFileId, kind: kind)
            guard let pid = prod.id else {
                isError = true; message = store.t("Không tạo được sản phẩm.", "Could not create product."); saving = false; return
            }

            // 2) Giá
            var pricePayload: [[String: Any]] = []
            if isAcc {
                let amount = Int(accPrice.filter { $0.isNumber }) ?? -1
                if amount >= 0 { pricePayload = [["label": "Mua acc", "amount": amount]] }
            } else {
                pricePayload = priceRows.compactMap { r in
                    let label = r.label.trimmingCharacters(in: .whitespaces)
                    let amount = Int(r.amount.filter { $0.isNumber }) ?? -1
                    guard !label.isEmpty, amount >= 0 else { return nil }
                    return ["label": label, "amount": amount]
                }
            }
            if !pricePayload.isEmpty {
                _ = try await store.api.adminStoreSetPrices(productId: pid, prices: pricePayload)
            }

            // 3) Lấy lại sản phẩm để biết id từng mốc giá rồi nhập key đúng mốc
            var keysAdded = 0
            if let saved = try? await store.api.storeProduct(pid) {
                if isAcc {
                    let txt = accKeys.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !txt.isEmpty, let firstPid = saved.prices.first?.id {
                        let r = try await store.api.adminStoreAddKeys(productId: pid, text: txt, priceId: firstPid)
                        keysAdded += countLines(txt); _ = r
                    }
                } else {
                    for row in priceRows {
                        let txt = row.keys.trimmingCharacters(in: .whitespacesAndNewlines)
                        let label = row.label.trimmingCharacters(in: .whitespaces)
                        guard !txt.isEmpty, !label.isEmpty,
                              let priceId = saved.prices.first(where: { $0.label == label })?.id else { continue }
                        _ = try await store.api.adminStoreAddKeys(productId: pid, text: txt, priceId: priceId)
                        keysAdded += countLines(txt)
                    }
                }
            }

            store.postProductNotification(
                body: store.t("Sản phẩm mới vừa được thêm vào cửa hàng:", "A new product was added to the store:") + " \(name)")
            onDone()
            isError = false
            message = store.t("Đã lưu xong!", "All saved!") + " \(name)" +
                      (keysAdded > 0 ? " · \(keysAdded) " + store.t("key/acc", "keys/accounts") : "")
            // Reset phần sản phẩm để thêm cái khác (giữ nguyên danh mục/thư mục đã chọn)
            name = ""; desc = ""; media = []; downloadUrl = ""; downloadFileId = nil
            priceRows = [QuickPriceRow()]; accPrice = ""; accKeys = ""
        } catch { isError = true; message = error.localizedDescription }
        saving = false
    }

    private func countLines(_ s: String) -> Int {
        s.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

// ---- Bảng giá theo thời hạn ----
struct EditPrice: Identifiable, Hashable {
    let id = UUID()
    var label: String = ""
    var amount: String = ""
}

struct StorePricesEditor: View {
    @EnvironmentObject var store: AppStore
    let productId: Int
    let initial: [StorePrice]
    var kind: String = "app"
    @State private var rows: [EditPrice] = []
    @State private var accPrice = ""          // acc: chỉ 1 giá tiền, không cần thời hạn
    @State private var message: String?
    @State private var isError = false

    private var isAcc: Bool { kind == "acc" }
    private let presets = ["1 giờ", "1 ngày", "1 tuần", "1 tháng", "Vĩnh viễn"]

    var body: some View {
        Form {
            if isAcc {
                // Acc game: chỉ cần giá tiền, KHÔNG có mốc thời hạn.
                Section(store.t("Giá bán acc", "Account price")) {
                    HStack {
                        TextField(store.t("Giá VND", "Price VND"), text: $accPrice).keyboardType(.numberPad)
                        Text("đ").foregroundStyle(.secondary)
                    }
                    Text(store.t("Acc game bán 1 giá cố định, khách mua xong nhận ngay 1 tài khoản.",
                                 "Game accounts sell at one fixed price; buyer receives 1 account instantly."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Section(store.t("Các mốc giá (theo thời hạn)", "Price tiers (by duration)")) {
                    ForEach($rows) { $r in
                        HStack {
                            TextField(store.t("Thời hạn (vd 1 ngày)", "Duration (e.g. 1 day)"), text: $r.label)
                            TextField(store.t("Giá VND", "Price VND"), text: $r.amount).keyboardType(.numberPad)
                                .frame(width: 110)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button { rows.append(EditPrice()) } label: {
                        Label(store.t("Thêm mốc giá", "Add price tier"), systemImage: "plus.circle")
                    }
                }
                Section(store.t("Mẫu nhanh", "Quick presets")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(presets, id: \.self) { p in
                                Button(p) { rows.append(EditPrice(label: p, amount: "")) }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            Section { Button(isAcc ? store.t("Lưu giá", "Save price") : store.t("Lưu bảng giá", "Save price table")) { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(isAcc ? store.t("Giá bán acc", "Account price") : store.t("Bảng giá", "Price table"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if isAcc {
                if accPrice.isEmpty, let first = initial.first { accPrice = "\(first.amount)" }
            } else if rows.isEmpty {
                rows = initial.map { EditPrice(label: $0.label, amount: "\($0.amount)") }
                if rows.isEmpty { rows = [EditPrice()] }
            }
        }
    }

    private func save() async {
        message = nil
        var payload: [[String: Any]] = []
        if isAcc {
            let amount = Int(accPrice.filter { $0.isNumber }) ?? -1
            if amount >= 0 { payload = [["label": "Mua acc", "amount": amount]] }
        } else {
            payload = rows.compactMap { r in
                let label = r.label.trimmingCharacters(in: .whitespaces)
                let amount = Int(r.amount.filter { $0.isNumber }) ?? -1
                guard !label.isEmpty, amount >= 0 else { return nil }
                return ["label": label, "amount": amount]
            }
        }
        do {
            let r = try await store.api.adminStoreSetPrices(productId: productId, prices: payload)
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Kho KEY / ACC ----
struct StoreKeysManager: View {
    @EnvironmentObject var store: AppStore
    let productId: Int
    @State private var info: StoreKeysInfo?
    @State private var prices: [StorePrice] = []
    @State private var kind = "app"            // app | acc
    @State private var selectedPriceId: Int?   // nil = dùng chung (mọi mốc)
    @State private var newKeys = ""
    @State private var message: String?
    @State private var isError = false
    @State private var showFileImporter = false

    private var isAcc: Bool { kind == "acc" }
    private func priceLabel(_ id: Int?) -> String {
        guard let id, let p = prices.first(where: { $0.id == id }) else { return store.t("(chưa gán mốc)", "(no tier)") }
        return p.label
    }

    var body: some View {
        Form {
            // Với Ứng dụng/Key: chọn mốc thời hạn để nhập key riêng cho từng khung giờ.
            if !isAcc && !prices.isEmpty {
                Section(store.t("Nhập key cho mốc thời hạn nào?", "Add keys for which tier?")) {
                    Picker(store.t("Mốc thời hạn", "Duration tier"), selection: $selectedPriceId) {
                        ForEach(prices) { p in
                            Text("\(p.label) · \(kFormatVND(p.amount))").tag(Int?.some(p.id))
                        }
                    }
                    Text(store.t("Mỗi mốc (giờ/ngày/tuần/tháng) có kho key RIÊNG. Khách mua mốc nào nhận key của mốc đó; hết mốc nào → mốc đó hiện 'Hết hàng', không mua được.",
                                 "Each tier (hour/day/week/month) has its OWN key stock. Buyers get the key of the tier they buy; when a tier runs out it shows 'Out of stock' and can't be bought."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if !isAcc && prices.isEmpty {
                Section {
                    Text(store.t("Chưa có mốc giá. Hãy vào 'Bảng giá theo thời hạn' tạo các mốc (1 giờ/ngày/tuần/tháng) trước, rồi quay lại nhập key cho từng mốc.",
                                 "No price tiers yet. Go to 'Price table by duration' to create tiers (1 hour/day/week/month) first, then return to add keys per tier."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section(isAcc ? store.t("Thêm tài khoản (mỗi dòng: user|pass)", "Add accounts (one per line: user|pass)") : store.t("Thêm key (mỗi dòng 1 key)", "Add keys (one per line)")) {
                TextEditor(text: $newKeys).frame(minHeight: 120)
                if isAcc {
                    Text(store.t("Ví dụ mỗi dòng: taikhoan1|matkhau1 — khách mua xong tự nhận 1 tài khoản.",
                                 "Each line e.g. account1|password1 — buyer auto-receives 1 account."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Button(isAcc ? store.t("Thêm tài khoản", "Add accounts") : store.t("Thêm key", "Add keys")) { Task { await addKeys() } }
                        .disabled(newKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button { showFileImporter = true } label: {
                        Label(store.t("Nhập file CSV/TXT", "Import CSV/TXT file"), systemImage: "doc.badge.plus").font(.caption)
                    }
                }
            }
            if let info {
                Section(store.t("Tồn kho:", "Stock:") + " \(info.available) " + store.t("khả dụng", "available") + " / \(info.total) " + store.t("tổng", "total")) {
                    Button(isAcc ? store.t("Xoá tất cả tài khoản khả dụng", "Delete all available accounts") : store.t("Xoá tất cả key khả dụng", "Delete all available keys"), role: .destructive) {
                        Task { await deleteAvailable() }
                    }
                }
                Section(isAcc ? store.t("Danh sách tài khoản", "Account list") : store.t("Danh sách key", "Key list")) {
                    if info.keys.isEmpty {
                        Text(isAcc ? store.t("Chưa có tài khoản nào.", "No accounts yet.") : store.t("Chưa có key nào.", "No keys yet.")).foregroundStyle(.secondary)
                    } else {
                        ForEach(info.keys) { k in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.keyText).font(.caption.monospaced()).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(k.status == "sold" ? store.t("đã bán", "sold") : store.t("khả dụng", "available"))
                                            .font(.caption2)
                                            .foregroundStyle(k.status == "sold" ? .orange : .green)
                                        if !isAcc {
                                            Text("· \(priceLabel(k.priceId))")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await deleteKey(k.id) }
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(isAcc ? store.t("Kho tài khoản (ACC)", "Account stock (ACC)") : store.t("Kho KEY", "KEY stock"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showFileImporter) {
            DocumentPicker(allowsMultipleSelection: false) { urls in
                if let url = urls.first { Task { await importFromFile(url) } }
            }
            .ignoresSafeArea()
        }
    }

    private func reload() async {
        info = try? await store.api.adminStoreListKeys(productId: productId)
        if let p = try? await store.api.storeProduct(productId) {
            prices = p.prices; kind = p.kind ?? "app"
            // App/Key: mặc định chọn mốc đầu nếu chưa chọn (bắt buộc gán key vào 1 mốc)
            if kind != "acc", selectedPriceId == nil { selectedPriceId = prices.first?.id }
        }
    }
    private func importFromFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            isError = true; message = store.t("Không đọc được file.", "Could not read file."); return
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        newKeys = lines.joined(separator: "\n")
        isError = false
        message = store.t("Đã tải", "Loaded") + " \(lines.count) " + store.t("key từ file. Bấm 'Thêm key' để lưu.", "keys from file. Tap 'Add keys' to save.")
    }
    private func addKeys() async {
        message = nil
        do {
            // ACC: gắn vào mốc giá duy nhất. App/Key: gắn theo mốc thời hạn đã chọn.
            let pid = isAcc ? prices.first?.id : selectedPriceId
            let r = try await store.api.adminStoreAddKeys(productId: productId, text: newKeys, priceId: pid)
            isError = false; message = r.message; newKeys = ""
            await reload()
        } catch { isError = true; message = error.localizedDescription }
    }
    private func deleteKey(_ id: Int) async {
        _ = try? await store.api.adminStoreDeleteKey(id)
        await reload()
    }
    private func deleteAvailable() async {
        message = nil
        do {
            let r = try await store.api.adminStoreDeleteAvailableKeys(productId: productId)
            isError = false; message = r.message
            await reload()
        } catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Đơn hàng đã bán (admin) ----
struct StoreAdminOrdersView: View {
    @EnvironmentObject var store: AppStore
    @State private var orders: [StoreAdminOrder] = []

    var body: some View {
        List {
            if orders.isEmpty {
                Text(store.t("Chưa có đơn nào.", "No orders yet.")).foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(o.productName).font(.subheadline.bold())
                            Spacer()
                            Text(o.status == "completed" ? store.t("đã thanh toán", "paid") : store.t("chờ", "pending"))
                                .font(.caption2)
                                .foregroundStyle(o.status == "completed" ? .green : .orange)
                        }
                        Text("\(kFormatVND(o.amount)) · @\(o.username)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(store.t("Đơn hàng", "Orders"))
        .navigationBarTitleDisplayMode(.inline)
        .task { orders = (try? await store.api.adminStoreOrders()) ?? [] }
        .refreshable { orders = (try? await store.api.adminStoreOrders()) ?? [] }
    }
}

// ---- Khuyến mãi nạp ví (%) — admin ----
struct StoreTopupBonusEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var percentText = ""
    @State private var message: String?
    @State private var isError = false
    private var percent: Int? { Int(percentText.filter { $0.isNumber }) }

    var body: some View {
        Form {
            Section(store.t("Phần trăm thưởng khi khách nạp ví", "Bonus percent on customer top-up")) {
                HStack {
                    TextField(store.t("Ví dụ: 20", "e.g. 20"), text: $percentText).keyboardType(.numberPad)
                    Text("%").foregroundStyle(.secondary)
                }
                if let p = percent, p > 0 {
                    Text(store.t("Khách nạp 100.000đ sẽ nhận", "A 100,000đ top-up gives") + " \(kFormatVND(100_000 + 100_000 * p / 100)) " + store.t("vào ví.", "in the wallet."))
                        .font(.caption).foregroundStyle(.pink)
                }
                Text(store.t("Đặt 0 để tắt khuyến mãi. Áp dụng cho VÍ cửa hàng (tách biệt với nâng cấp PRO của app chính).",
                             "Set 0 to disable. Applies to the store WALLET (separate from the main app's PRO upgrade)."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section { Button(store.t("Lưu", "Save")) { Task { await save() } }.disabled(percent == nil) }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(store.t("Khuyến mãi", "Promotions"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let r = try? await store.api.adminGetTopupBonus() { percentText = "\(r.percent)" }
        }
    }
    private func save() async {
        guard let p = percent else { return }
        message = nil
        do { let r = try await store.api.adminSetTopupBonus(percent: p); isError = false; message = r.message }
        catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Kho hàng (tồn kho) — admin ----
struct StoreInventoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var inv: StoreInventory?

    var body: some View {
        List {
            if let inv {
                Section {
                    HStack {
                        invStat(store.t("Còn lại", "Available"), "\(inv.totalAvailable)", .green)
                        invStat(store.t("Đã bán", "Sold"), "\(inv.totalSold)", .blue)
                        invStat(store.t("Hết hàng", "Out of stock"), "\(inv.outOfStock)", inv.outOfStock > 0 ? .red : .secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section(store.t("Sản phẩm", "Products") + " (\(inv.products.count)) — " + store.t("ưu tiên hết/sắp hết", "out/low stock first")) {
                    if inv.products.isEmpty {
                        Text(store.t("Chưa có sản phẩm nào.", "No products yet.")).foregroundStyle(.secondary)
                    }
                    ForEach(inv.products) { p in
                        HStack(spacing: 10) {
                            Image(systemName: (p.kind ?? "app") == "acc" ? "gamecontroller.fill" : "key.fill")
                                .foregroundStyle((p.kind ?? "app") == "acc" ? .purple : Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.bold()).lineLimit(1)
                                Text("\(p.categoryName) › \(p.folderName)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(p.available == 0 ? store.t("HẾT", "OUT") : store.t("Còn", "Left") + " \(p.available)")
                                    .font(.caption.bold())
                                    .foregroundStyle(p.available == 0 ? .red : (p.available <= 5 ? .orange : .green))
                                Text(store.t("đã bán", "sold") + " \(p.sold)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle(store.t("Kho hàng", "Inventory"))
        .navigationBarTitleDisplayMode(.inline)
        .task { inv = try? await store.api.adminStoreInventory() }
        .refreshable { inv = try? await store.api.adminStoreInventory() }
    }

    private func invStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// ======================== Nạp/Trừ ví khách hàng thủ công ========================
struct AdminWalletAdjustView: View {
    @EnvironmentObject var store: AppStore
    var prefillUser: String = ""              // mở sẵn với 1 khách (từ danh sách người dùng)
    @State private var userIdentifier = ""    // username hoặc publicId
    @State private var amountText = ""
    @State private var note = ""
    @State private var isDeduct = false       // false = nạp, true = trừ
    @State private var processing = false
    @State private var message: String?
    @State private var isError = false
    @State private var history: [WalletAdjustRecord] = []

    private var amount: Int? { Int(amountText.filter { $0.isNumber }) }
    private let presets = [10_000, 50_000, 100_000, 200_000, 500_000]

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "dollarsign.arrow.circlepath",
                            title: store.t("Điều chỉnh ví", "Adjust wallet"),
                            subtitle: store.t("Nạp hoặc trừ tiền ví khách hàng thủ công",
                                              "Manually add or deduct customer wallet funds"))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section(store.t("Khách hàng", "Customer")) {
                TextField(store.t("Username hoặc ID khách hàng", "Customer username or ID"), text: $userIdentifier)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .onAppear { if userIdentifier.isEmpty && !prefillUser.isEmpty { userIdentifier = prefillUser } }

            Section(store.t("Loại thao tác", "Operation type")) {
                Picker("", selection: $isDeduct) {
                    Text(store.t("Nạp tiền (+)", "Add (+)")).tag(false)
                    Text(store.t("Trừ tiền (-)", "Deduct (-)")).tag(true)
                }.pickerStyle(.segmented)
            }

            Section(isDeduct ? store.t("Số tiền trừ", "Deduct amount") : store.t("Số tiền nạp", "Add amount")) {
                HStack {
                    TextField(store.t("Nhập số tiền (VND)", "Enter amount (VND)"), text: $amountText).keyboardType(.numberPad)
                    Text("đ").foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { v in
                            Button(kFormatVND(v)) { amountText = "\(v)" }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                        }
                    }
                }
            }

            Section(store.t("Ghi chú", "Note")) {
                TextField(store.t("Lý do (tuỳ chọn)", "Reason (optional)"), text: $note, axis: .vertical).lineLimit(1...3)
            }

            Section {
                Button {
                    Task { await adjust() }
                } label: {
                    HStack {
                        if processing { ProgressView().tint(.white) }
                        Text(processing ? store.t("Đang xử lý...", "Processing...") : (isDeduct ? store.t("Trừ ví", "Deduct wallet") : store.t("Nạp ví", "Add to wallet")))
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(userIdentifier.isEmpty || (amount ?? 0) < 1 ? Color.gray :
                                (isDeduct ? Color.red : Color.green))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(userIdentifier.isEmpty || (amount ?? 0) < 1 || processing)
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(isError ? .red : .green).font(.footnote)
                }
            }

            if !history.isEmpty {
                Section(store.t("Lịch sử thao tác (phiên này)", "Operation history (this session)")) {
                    ForEach(history) { r in
                        HStack {
                            Image(systemName: r.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(r.delta >= 0 ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.user).font(.caption.bold())
                                Text(r.note).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((r.delta >= 0 ? "+" : "") + kFormatVND(r.delta))
                                .font(.caption.bold())
                                .foregroundStyle(r.delta >= 0 ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle(store.t("Điều chỉnh ví", "Adjust wallet"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func adjust() async {
        guard let amt = amount, amt > 0, !userIdentifier.isEmpty else { return }
        processing = true; message = nil; isError = false
        let delta = isDeduct ? -amt : amt
        do {
            let resp = try await store.api.adminAdjustStoreWallet(
                userIdentifier: userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                delta: delta,
                note: note.isEmpty ? (isDeduct ? "Admin trừ ví thủ công" : "Admin nạp ví thủ công") : note)
            message = resp.message
            let record = WalletAdjustRecord(user: userIdentifier, delta: delta,
                                            note: note.isEmpty ? resp.message : note)
            history.insert(record, at: 0)
            // Gửi thông báo local cho admin
            store.postLocalNotification(
                title: isDeduct ? "Đã trừ ví" : "Đã nạp ví",
                body: "\(isDeduct ? "-" : "+")\(kFormatVND(amt)) cho \(userIdentifier)")
            amountText = ""; note = ""; userIdentifier = ""
        } catch {
            isError = true; message = error.localizedDescription
        }
        processing = false
    }
}

struct WalletAdjustRecord: Identifiable {
    let id = UUID()
    let user: String
    let delta: Int
    let note: String
}

// ======================== Thống kê & Phân tích (Admin) ========================
struct AdminAnalyticsView: View {
    @EnvironmentObject var store: AppStore
    @State private var stats: AdminStats?
    @State private var orders: [StoreAdminOrder] = []
    @State private var loading = false

    private var topProducts: [(name: String, count: Int, revenue: Int)] {
        var map: [String: (Int, Int)] = [:]
        for o in orders where o.status == "completed" {
            let cur = map[o.productName] ?? (0, 0)
            map[o.productName] = (cur.0 + 1, cur.1 + o.amount)
        }
        return map.map { (name: $0.key, count: $0.value.0, revenue: $0.value.1) }
            .sorted { $0.revenue > $1.revenue }
            .prefix(5).map { $0 }
    }

    private var storeRevenue: Int {
        orders.filter { $0.status == "completed" }.reduce(0) { $0 + $1.amount }
    }
    private var completedOrderCount: Int {
        orders.filter { $0.status == "completed" }.count
    }

    var body: some View {
        List {
            if loading && stats == nil {
                HStack { Spacer(); ProgressView(store.t("Đang tải...", "Loading...")); Spacer() }
            } else if let s = stats {
                Section(store.t("Doanh thu cửa hàng", "Store revenue")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Tổng cộng", "Total"), kFormatVND(storeRevenue), .green)
                        analyticsCard(store.t("Đơn hoàn tất", "Completed orders"), "\(completedOrderCount)", .blue)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section(store.t("Người dùng", "Users")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Tổng users", "Total users"), "\(s.totalUsers)", .purple)
                        analyticsCard(store.t("7 ngày mới", "New (7 days)"), "+\(s.newUsers7d)", .orange)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section(store.t("AI & Hội thoại", "AI & Conversations")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Hội thoại", "Conversations"), "\(s.totalConversations)", .teal)
                        analyticsCard(store.t("Tin nhắn", "Messages"), "\(s.totalMessages)", Theme.accent)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Doanh thu AI", "AI revenue"), kFormatVND(s.revenueTotal), .green)
                        analyticsCard(store.t("30 ngày", "30 days"), kFormatVND(s.revenue30d), .mint)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if !topProducts.isEmpty {
                    Section(store.t("Top sản phẩm bán chạy", "Top selling products")) {
                        let maxRev = topProducts.first.map { $0.revenue } ?? 1
                        ForEach(topProducts.indices, id: \.self) { i in
                            let item = topProducts[i]
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name).font(.subheadline.bold()).lineLimit(1)
                                    Spacer()
                                    Text(kFormatVND(item.revenue))
                                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                                }
                                HStack(spacing: 6) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color(.tertiarySystemBackground))
                                                .frame(height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Theme.accent)
                                                .frame(width: geo.size.width * CGFloat(item.revenue) / CGFloat(maxRev),
                                                       height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                    Text("\(item.count) " + store.t("đơn", "orders")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !s.topProviders.isEmpty {
                    Section(store.t("AI provider phổ biến", "Popular AI providers")) {
                        let maxCount = s.topProviders.first?.count ?? 1
                        ForEach(s.topProviders, id: \.provider) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(p.provider).font(.subheadline)
                                    Spacer()
                                    Text("\(p.count) " + store.t("lượt", "uses")).font(.caption2).foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.tertiarySystemBackground))
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Theme.purple)
                                            .frame(width: geo.size.width * CGFloat(p.count) / CGFloat(maxCount),
                                                   height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if !loading {
                Text(store.t("Không tải được thống kê.", "Could not load statistics.")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.t("Thống kê & Phân tích", "Statistics & Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func analyticsCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        async let s = store.api.adminStats()
        async let o = store.api.adminStoreOrders()
        stats = try? await s
        orders = (try? await o) ?? []
        loading = false
    }
}

// ======================== Quản lý mã khuyến mãi (Admin) ========================
struct AdminPromoCodesView: View {
    @EnvironmentObject var store: AppStore
    @State private var codes: [PromoCode] = []
    @State private var loading = false
    @State private var showAdd = false
    @State private var message: String?

    // Form tạo mới
    @State private var newCode = ""
    @State private var discountType = "percent"
    @State private var discountValue = ""
    @State private var minAmount = ""
    @State private var maxUses = ""

    var body: some View {
        List {
            if loading {
                Section { ProgressView() }
            }
            Section {
                ForEach(Array(codes.enumerated()), id: \.offset) { _, promo in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(promo.code).font(.headline.monospaced())
                            Spacer()
                            Text(promo.discountType == "percent"
                                 ? "-\(promo.discountValue)%"
                                 : "-\(kFormatVND(promo.discountValue))")
                                .font(.caption.bold()).foregroundStyle(.green)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        HStack(spacing: 12) {
                            Label("\(promo.usedCount)\(promo.maxUses > 0 ? "/\(promo.maxUses)" : "") " + store.t("lượt", "uses"),
                                  systemImage: "person.2")
                            if promo.minAmount > 0 {
                                Label(store.t("Tối thiểu", "Min") + " \(kFormatVND(promo.minAmount))", systemImage: "cart")
                            }
                            if promo.expiresAt > 0 {
                                Label(Date(timeIntervalSince1970: TimeInterval(promo.expiresAt))
                                        .formatted(.dateTime.day().month().year()),
                                      systemImage: "calendar")
                            }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await deleteCode(promo.id) } } label: {
                            Label(store.t("Xoá", "Delete"), systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text(store.t("Danh sách mã", "Code list") + " (\(codes.count))")
                    Spacer()
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(store.t("Mã khuyến mãi", "Promo codes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section(store.t("Mã giảm giá", "Discount code")) {
                    TextField(store.t("Tên mã (VD: SALE50)", "Code name (e.g. SALE50)"), text: $newCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker(store.t("Loại giảm", "Discount type"), selection: $discountType) {
                        Text(store.t("Phần trăm (%)", "Percent (%)")).tag("percent")
                        Text(store.t("Số tiền cố định (đ)", "Fixed amount (đ)")).tag("fixed")
                    }
                    TextField(discountType == "percent" ? store.t("Giảm bao nhiêu % (VD: 20)", "Discount % (e.g. 20)") : store.t("Giảm bao nhiêu đ (VD: 10000)", "Discount đ (e.g. 10000)"),
                              text: $discountValue)
                        .keyboardType(.numberPad)
                }
                Section(store.t("Điều kiện", "Conditions")) {
                    TextField(store.t("Đơn tối thiểu (VD: 50000, để trống = không giới hạn)", "Min order (e.g. 50000, empty = no limit)"), text: $minAmount)
                        .keyboardType(.numberPad)
                    TextField(store.t("Số lần dùng tối đa (để trống = không giới hạn)", "Max uses (empty = unlimited)"), text: $maxUses)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(store.t("Tạo mã mới", "Create new code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.t("Huỷ", "Cancel")) { showAdd = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Tạo", "Create")) { Task { await createCode() } }
                        .bold()
                        .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty || discountValue.isEmpty)
                }
            }
        }
    }

    private func reload() async {
        loading = true
        codes = (try? await store.api.adminListPromoCodes()) ?? []
        loading = false
    }

    private func createCode() async {
        let code = newCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty, let value = Int(discountValue), value > 0 else { return }
        let min = Int(minAmount) ?? 0
        let max = Int(maxUses) ?? 0
        do {
            _ = try await store.api.adminCreatePromoCode(
                code: code, discountType: discountType, discountValue: value,
                minAmount: min, maxUses: max, expiresAt: 0)
            showAdd = false
            newCode = ""; discountValue = ""; minAmount = ""; maxUses = ""
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteCode(_ id: Int) async {
        _ = try? await store.api.adminDeletePromoCode(id)
        await reload()
    }
}

// ======================== Gửi Push Notification (Admin) ========================
struct AdminPushNotificationView: View {
    @EnvironmentObject var store: AppStore
    @State private var notifTitle = ""
    @State private var notifBody = ""
    @State private var sending = false
    @State private var result: String?
    @State private var isError = false
    @State private var deviceStats: PushDeviceStats?

    var body: some View {
        Form {
            if let stats = deviceStats {
                Section(store.t("Thiết bị đã đăng ký", "Registered devices")) {
                    Label("\(stats.totalDevices) " + store.t("thiết bị", "devices"), systemImage: "iphone")
                    Label("\(stats.totalUsers) " + store.t("người dùng", "users"), systemImage: "person.2")
                }
            }

            Section(store.t("Nội dung thông báo", "Notification content")) {
                TextField(store.t("Tiêu đề", "Title"), text: $notifTitle)
                TextField(store.t("Nội dung", "Body"), text: $notifBody, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    Task { await sendNotif() }
                } label: {
                    HStack {
                        if sending { ProgressView().padding(.trailing, 4) }
                        Text(sending ? store.t("Đang gửi...", "Sending...") : store.t("Gửi cho tất cả người dùng", "Send to all users"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(sending || notifTitle.isEmpty || notifBody.isEmpty)
            }

            if let result {
                Section {
                    Text(result).foregroundStyle(isError ? .red : .green).font(.footnote)
                }
            }

            Section(store.t("Hướng dẫn cấu hình APNs", "APNs setup guide")) {
                Text("""
                Để gửi push notification thật, cần cấu hình các biến môi trường trên server:
                • APNS_KEY_ID — Key ID từ Apple Developer
                • APNS_TEAM_ID — Team ID của tài khoản
                • APNS_BUNDLE_ID — Bundle ID của app
                • APNS_KEY_PATH — Đường dẫn file .p8
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.t("Gửi thông báo", "Send notification"))
        .navigationBarTitleDisplayMode(.inline)
        .task { deviceStats = try? await store.api.adminPushDeviceStats() }
    }

    private func sendNotif() async {
        sending = true; result = nil; isError = false
        do {
            let r = try await store.api.adminSendPushNotification(title: notifTitle, body: notifBody)
            result = r.message; isError = false
        } catch {
            result = error.localizedDescription; isError = true
        }
        sending = false
    }
}
