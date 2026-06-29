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
            Section {
                TextField(store.t("Tên cửa hàng / logo", "Store name / logo"), text: $logoName)
                TextField(store.t("Link logo: VIDEO (MP4) hoặc PNG / GIF / JPEG / WEBP",
                                  "Logo link: VIDEO (MP4) or PNG / GIF / JPEG / WEBP"), text: $logoUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !logoUrl.isEmpty {
                    HStack {
                        Spacer()
                        StoreThumb(media: [StoreMedia(type: isVideoLink(logoUrl) ? "video" : "image", url: logoUrl)],
                                   height: 60)
                            .frame(width: 60, height: 60)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                }
            } header: {
                Text(store.t("Logo cửa hàng", "Store logo"))
            } footer: {
                Text(store.t("Logo có thể là VIDEO (dán link .mp4) hoặc ảnh PNG / GIF / JPEG / WEBP — giống các mục khác.",
                             "The logo can be a VIDEO (paste an .mp4 link) or a PNG / GIF / JPEG / WEBP image — like the other sections."))
                    .font(.caption2)
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
                    StoreMediaCarousel(media: [StoreMedia(type: bannerType, url: bannerUrl)], height: 120,
                                       videoFit: true)   // xem trước đúng như hero (video đủ khung)
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
