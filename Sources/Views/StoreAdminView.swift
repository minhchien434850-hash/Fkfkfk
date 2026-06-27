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
                    Picker("Loại", selection: $m.type) {
                        Text("Ảnh / GIF").tag("image")
                        Text("Video").tag("video")
                    }.pickerStyle(.segmented)
                    TextField("Dán link ảnh / GIF / PNG / JPEG / WEBP / MP4...", text: $m.url)
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
                    Label("Thêm ô dán link thủ công", systemImage: "plus.circle")
                }
            }
            Button {
                showConverter = true
            } label: {
                Label("Chuyển đổi ảnh → link GIF / PNG / JPEG", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(store.accentColor)
            }
            if let uploadError {
                Text(uploadError).font(.caption2).foregroundStyle(.red)
            }
        } header: {
            Text("Ảnh / Video (tối đa 5)")
        } footer: {
            Text("Chọn ảnh/video từ máy để tự tải lên, hoặc dán link từ Imgur, Cloudinary, Giphy... Hoặc bấm \"Chuyển đổi\" để tạo link từ ảnh.")
                .font(.caption2)
        }
        .onChange(of: picker) { item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
        .sheet(isPresented: $showConverter) {
            MediaConverterView().environmentObject(store)
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StoreConfigEditor()
                    } label: {
                        Label("Giao diện cửa hàng (logo, nền)", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        StoreContactsEditor()
                    } label: {
                        Label("Liên hệ admin & Nhóm cộng đồng", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    NavigationLink {
                        StoreTopupBonusEditor()
                    } label: {
                        Label("Khuyến mãi nạp ví (%)", systemImage: "percent")
                    }
                    NavigationLink {
                        StoreInventoryView()
                    } label: {
                        Label("Kho hàng (tồn kho)", systemImage: "shippingbox")
                    }
                    NavigationLink {
                        StoreAdminOrdersView()
                    } label: {
                        Label("Đơn hàng đã bán", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        StoreKeysBackupView()
                    } label: {
                        Label("Sao lưu KEY / ACC đã bán", systemImage: "externaldrive.badge.checkmark")
                    }
                    NavigationLink {
                        StoreStructureBackupView()
                    } label: {
                        Label("Backup toàn bộ cửa hàng (JSON)", systemImage: "arrow.down.doc.fill")
                    }
                    NavigationLink {
                        StoreRestoreBackupView()
                    } label: {
                        Label("Khôi phục backup JSON", systemImage: "arrow.up.doc.fill")
                    }
                    NavigationLink {
                        AdminAnalyticsView()
                    } label: {
                        Label("Thống kê & Phân tích", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        AdminPromoCodesView()
                    } label: {
                        Label("Mã khuyến mãi", systemImage: "tag.fill")
                    }
                    NavigationLink {
                        AdminPushNotificationView()
                    } label: {
                        Label("Gửi thông báo (Push)", systemImage: "bell.badge.fill")
                    }
                    NavigationLink {
                        AdminWalletAdjustView()
                    } label: {
                        Label("Nạp / Trừ ví khách hàng", systemImage: "dollarsign.arrow.circlepath")
                    }
                }

                Section("Danh mục sản phẩm (\(categories.count))") {
                    Button { newCategory = true } label: {
                        Label("Thêm danh mục mới", systemImage: "plus.circle.fill")
                    }
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
                                    Text("Bấm để quản lý thư mục con")
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
                }

                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle("Quản trị cửa hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
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
    @State private var message: String?
    @State private var isError = false
    @AppStorage("storeCfgName") private var cfgName: String = ""
    @AppStorage("storeCfgLogo") private var cfgLogo: String = ""
    @AppStorage("storeCfgBannerType") private var cfgBannerType: String = "image"
    @AppStorage("storeCfgBannerUrl") private var cfgBannerUrl: String = ""

    var body: some View {
        Form {
            Section("Logo cửa hàng") {
                TextField("Tên cửa hàng / logo", text: $logoName)
                TextField("Link ảnh logo (PNG / GIF / JPEG / WEBP)", text: $logoUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Hiệu ứng tên/logo cửa hàng") {
                HStack { Spacer()
                    AnimatedStoreLogo(text: logoName.isEmpty ? "KENIOS STORE" : logoName,
                                      effect: logoEffect, fontStyle: logoFont, anim: logoAnim, size: 28)
                    Spacer() }
                Picker("Hiệu ứng màu", selection: $logoEffect) {
                    ForEach(kLogoEffects, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Kiểu chữ (font)", selection: $logoFont) {
                    ForEach(kLogoFonts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Chuyển động", selection: $logoAnim) {
                    ForEach(kLogoAnims, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section("Nền cửa hàng (full màn hình)") {
                Picker("Loại nền", selection: $bgType) {
                    Text("Không").tag("none")
                    Text("Ảnh / GIF").tag("image")
                    Text("Video / MP4").tag("video")
                }.pickerStyle(.segmented)
                if bgType != "none" {
                    TextField("Dán link nền (GIF / PNG / JPEG / WEBP / MP4)", text: $bgUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("Nền chạy sâu phía dưới, mọi nội dung/nút vẫn nằm bên trên và bấm được.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section { Button("Lưu giao diện") { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle("Giao diện cửa hàng")
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
        }
    }
    private func save() async {
        message = nil
        do {
            let r = try await store.api.adminStoreSetConfig(
                logoName: logoName, logoUrl: logoUrl,
                bannerType: bannerType, bannerUrl: bannerUrl,
                logoEffect: logoEffect, logoFont: logoFont, logoAnim: logoAnim,
                bgType: bgType, bgUrl: bgUrl)
            // Lưu cache ngay để các màn khác giữ tên/logo mới kể cả khi tải lại lúc mạng chậm
            cfgName = logoName; cfgLogo = logoUrl; cfgBannerType = bannerType; cfgBannerUrl = bannerUrl
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
                Section("Tên danh mục") {
                    TextField("Ví dụ: Game Mod, Tài khoản, Phần mềm...", text: $name)
                }
                MediaEditor(media: $media)
                Section { Button("Lưu danh mục") { Task { await save() } }.disabled(name.isEmpty) }
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(category == nil ? "Thêm danh mục" : "Sửa danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
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
            Section("Thư mục con (\(folders.count))") {
                Button { newFolder = true } label: {
                    Label("Thêm thư mục con", systemImage: "plus.circle.fill")
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
                Section("Tên thư mục con") {
                    TextField("Ví dụ: Liên Quân, PUBG, Free Fire...", text: $name)
                }
                MediaEditor(media: $media)
                Section { Button("Lưu thư mục") { Task { await save() } }.disabled(name.isEmpty) }
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(folder == nil ? "Thêm thư mục" : "Sửa thư mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
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
            Section("Sản phẩm (\(products.count))") {
                Button { newProduct = true } label: {
                    Label("Thêm sản phẩm", systemImage: "plus.circle.fill")
                }
                ForEach(products) { p in
                    NavigationLink {
                        StoreProductEditor(folderId: folder.id, product: p) { Task { await reload() } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name)
                            HStack(spacing: 6) {
                                Text("\(p.prices.count) mốc giá")
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
                Section("Thông tin sản phẩm") {
                    Picker("Loại", selection: $kind) {
                        Text("Ứng dụng / Key").tag("app")
                        Text("Acc game").tag("acc")
                    }.pickerStyle(.segmented)
                    TextField("Tên sản phẩm", text: $name)
                    TextField("Mô tả (tuỳ chọn)", text: $desc, axis: .vertical).lineLimit(1...4)
                    Text(kind == "acc"
                         ? "Acc game: mỗi dòng trong kho là 1 tài khoản (vd user|pass). Khách mua xong tự nhận 1 acc."
                         : "Ứng dụng/Key: mỗi dòng trong kho là 1 key. Khách mua xong tự nhận 1 key + bản tải.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MediaEditor(media: $media)
                Section("Bản tải (link hoặc file)") {
                    TextField("Dán link tải game/app", text: $downloadUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            if uploading { ProgressView().padding(.trailing, 4) }
                            Label(downloadFileId != nil ? "Đã có file (#\(downloadFileId!)) — đổi file"
                                                        : "Tải file lên (không giới hạn dung lượng)",
                                  systemImage: "arrow.up.doc")
                        }
                    }.disabled(uploading)
                    Text("Khách mua xong sẽ thấy nút 'Tải game' đồng bộ với link/file ở đây.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Lưu sản phẩm") { Task { await save() } }.disabled(name.isEmpty) }

                if let pid = productId {
                    Section("Cấu hình bán") {
                        NavigationLink {
                            StorePricesEditor(productId: pid, initial: product?.prices ?? [], kind: kind)
                        } label: {
                            Label(kind == "acc" ? "Giá bán acc" : "Bảng giá theo thời hạn",
                                  systemImage: "tag")
                        }
                        NavigationLink {
                            StoreKeysManager(productId: pid)
                        } label: {
                            Label(kind == "acc" ? "Kho tài khoản (ACC)" : "Kho KEY sản phẩm",
                                  systemImage: kind == "acc" ? "person.text.rectangle" : "key")
                        }
                    }
                } else {
                    Text("Lưu sản phẩm trước để thêm giá & key/tài khoản.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
            }
            .navigationTitle(product == nil ? "Thêm sản phẩm" : "Sửa sản phẩm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onAppear {
                if let p = product {
                    name = p.name; desc = p.description; media = mediaToEdit(p.media)
                    kind = p.kind ?? "app"
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await uploadFile(url) }
                }
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
            isError = false; message = "Đã lưu sản phẩm."
            // Thông báo đến người dùng khi có sản phẩm mới (không phải chỉnh sửa)
            if isNew {
                store.postProductNotification(
                    body: "Sản phẩm mới vừa được thêm vào cửa hàng: \(name)")
            }
            onDone()
        } catch { isError = true; message = error.localizedDescription }
    }

    private func uploadFile(_ url: URL) async {
        uploading = true; message = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let r = try await store.api.uploadFileRaw(name: url.lastPathComponent,
                                                      category: "store", fileURL: url)
            downloadFileId = r.id
            isError = false; message = "Đã tải file lên (#\(r.id)). Nhớ bấm Lưu sản phẩm."
        } catch { isError = true; message = error.localizedDescription }
        uploading = false
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
                Section("Giá bán acc") {
                    HStack {
                        TextField("Giá VND", text: $accPrice).keyboardType(.numberPad)
                        Text("đ").foregroundStyle(.secondary)
                    }
                    Text("Acc game bán 1 giá cố định, khách mua xong nhận ngay 1 tài khoản.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Section("Các mốc giá (theo thời hạn)") {
                    ForEach($rows) { $r in
                        HStack {
                            TextField("Thời hạn (vd 1 ngày)", text: $r.label)
                            TextField("Giá VND", text: $r.amount).keyboardType(.numberPad)
                                .frame(width: 110)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button { rows.append(EditPrice()) } label: {
                        Label("Thêm mốc giá", systemImage: "plus.circle")
                    }
                }
                Section("Mẫu nhanh") {
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
            Section { Button(isAcc ? "Lưu giá" : "Lưu bảng giá") { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(isAcc ? "Giá bán acc" : "Bảng giá")
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
        guard let id, let p = prices.first(where: { $0.id == id }) else { return "Dùng chung" }
        return p.label
    }

    var body: some View {
        Form {
            // Với Ứng dụng/Key: chọn mốc thời hạn để nhập key riêng cho từng khung giờ.
            if !isAcc && !prices.isEmpty {
                Section("Nhập key cho mốc thời hạn nào?") {
                    Picker("Mốc thời hạn", selection: $selectedPriceId) {
                        Text("Dùng chung (mọi mốc)").tag(Int?.none)
                        ForEach(prices) { p in
                            Text("\(p.label) · \(kFormatVND(p.amount))").tag(Int?.some(p.id))
                        }
                    }
                    Text("Mỗi mốc (giờ/ngày/tuần/tháng) có kho key riêng. Khách mua mốc nào sẽ nhận key của mốc đó; nếu mốc đó hết thì lấy key 'Dùng chung'.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if !isAcc && prices.isEmpty {
                Section {
                    Text("Chưa có mốc giá. Hãy vào 'Bảng giá theo thời hạn' tạo các mốc (1 giờ/ngày/tuần/tháng) trước, rồi quay lại nhập key cho từng mốc.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section(isAcc ? "Thêm tài khoản (mỗi dòng: user|pass)" : "Thêm key (mỗi dòng 1 key)") {
                TextEditor(text: $newKeys).frame(minHeight: 120)
                if isAcc {
                    Text("Ví dụ mỗi dòng: taikhoan1|matkhau1 — khách mua xong tự nhận 1 tài khoản.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Button(isAcc ? "Thêm tài khoản" : "Thêm key") { Task { await addKeys() } }
                        .disabled(newKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button { showFileImporter = true } label: {
                        Label("Nhập file CSV/TXT", systemImage: "doc.badge.plus").font(.caption)
                    }
                }
            }
            if let info {
                Section("Tồn kho: \(info.available) khả dụng / \(info.total) tổng") {
                    Button(isAcc ? "Xoá tất cả tài khoản khả dụng" : "Xoá tất cả key khả dụng", role: .destructive) {
                        Task { await deleteAvailable() }
                    }
                }
                Section(isAcc ? "Danh sách tài khoản" : "Danh sách key") {
                    if info.keys.isEmpty {
                        Text(isAcc ? "Chưa có tài khoản nào." : "Chưa có key nào.").foregroundStyle(.secondary)
                    } else {
                        ForEach(info.keys) { k in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.keyText).font(.caption.monospaced()).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(k.status == "sold" ? "đã bán" : "khả dụng")
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
        .navigationTitle(isAcc ? "Kho tài khoản (ACC)" : "Kho KEY")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.plainText, .text, .data,
                                            UTType(filenameExtension: "csv") ?? .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await importFromFile(url) }
            }
        }
    }

    private func reload() async {
        info = try? await store.api.adminStoreListKeys(productId: productId)
        if let p = try? await store.api.storeProduct(productId) {
            prices = p.prices; kind = p.kind ?? "app"
        }
    }
    private func importFromFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            isError = true; message = "Không đọc được file."; return
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        newKeys = lines.joined(separator: "\n")
        isError = false
        message = "Đã tải \(lines.count) key từ file. Bấm 'Thêm key' để lưu."
    }
    private func addKeys() async {
        message = nil
        do {
            // ACC: không gắn mốc thời hạn. App/Key: gắn theo mốc đã chọn (nil = dùng chung).
            let pid = isAcc ? nil : selectedPriceId
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
                Text("Chưa có đơn nào.").foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(o.productName).font(.subheadline.bold())
                            Spacer()
                            Text(o.status == "completed" ? "đã thanh toán" : "chờ")
                                .font(.caption2)
                                .foregroundStyle(o.status == "completed" ? .green : .orange)
                        }
                        Text("\(kFormatVND(o.amount)) · @\(o.username)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Đơn hàng")
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
            Section("Phần trăm thưởng khi khách nạp ví") {
                HStack {
                    TextField("Ví dụ: 20", text: $percentText).keyboardType(.numberPad)
                    Text("%").foregroundStyle(.secondary)
                }
                if let p = percent, p > 0 {
                    Text("Khách nạp 100.000đ sẽ nhận \(kFormatVND(100_000 + 100_000 * p / 100)) vào ví.")
                        .font(.caption).foregroundStyle(.pink)
                }
                Text("Đặt 0 để tắt khuyến mãi. Áp dụng cho VÍ cửa hàng (tách biệt với nâng cấp PRO của app chính).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section { Button("Lưu") { Task { await save() } }.disabled(percent == nil) }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle("Khuyến mãi nạp ví")
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
                        invStat("Còn lại", "\(inv.totalAvailable)", .green)
                        invStat("Đã bán", "\(inv.totalSold)", .blue)
                        invStat("Hết hàng", "\(inv.outOfStock)", inv.outOfStock > 0 ? .red : .secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Sản phẩm (\(inv.products.count)) — ưu tiên hết/sắp hết") {
                    if inv.products.isEmpty {
                        Text("Chưa có sản phẩm nào.").foregroundStyle(.secondary)
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
                                Text(p.available == 0 ? "HẾT" : "Còn \(p.available)")
                                    .font(.caption.bold())
                                    .foregroundStyle(p.available == 0 ? .red : (p.available <= 5 ? .orange : .green))
                                Text("đã bán \(p.sold)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle("Kho hàng")
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

// ---- Sao lưu KEY/ACC đã bán (admin) ----
struct StoreKeysBackupView: View {
    @EnvironmentObject var store: AppStore
    @State private var backup: StoreKeysBackup?

    var body: some View {
        List {
            if let b = backup {
                Section("Đã bán: \(b.total)") {
                    if b.entries.isEmpty {
                        Text("Chưa có key/acc nào được bán.").foregroundStyle(.secondary)
                    }
                }
                ForEach(b.entries) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(e.productName).font(.subheadline.bold())
                            if (e.kind ?? "app") == "acc" {
                                Text("acc").font(.caption2).foregroundStyle(.purple)
                            }
                            Spacer()
                            Text(kFormatVND(e.amount)).font(.caption).foregroundStyle(Theme.accent)
                        }
                        Text(e.key).font(.caption.monospaced()).textSelection(.enabled)
                        Text("@\(e.username) · ID \(e.publicId ?? "-") · \(timeText(e.time))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle("Sao lưu KEY/ACC")
        .navigationBarTitleDisplayMode(.inline)
        .task { backup = try? await store.api.adminStoreKeysBackup() }
        .refreshable { backup = try? await store.api.adminStoreKeysBackup() }
    }

    private func timeText(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

// ======================== Backup toàn bộ cấu trúc cửa hàng (JSON) ========================
struct StoreStructureBackupView: View {
    @EnvironmentObject var store: AppStore
    @State private var loading = false
    @State private var backupURL: URL?
    @State private var error: String?
    @State private var progress = ""

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "arrow.down.doc.fill",
                            title: "Backup cửa hàng",
                            subtitle: "Xuất toàn bộ danh mục · thư mục · sản phẩm ra file JSON")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section("Xuất dữ liệu") {
                Button {
                    Task { await createBackup() }
                } label: {
                    HStack {
                        if loading { ProgressView().padding(.trailing, 4) }
                        Label(loading ? "Đang xuất..." : "Tạo file JSON backup",
                              systemImage: "arrow.down.doc.fill")
                    }
                }
                .disabled(loading)
                if !progress.isEmpty {
                    Text(progress).font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let url = backupURL {
                Section("Sẵn sàng lưu") {
                    ShareLink(item: url, preview: SharePreview(url.lastPathComponent,
                                                               icon: Image(systemName: "doc.badge.arrow.up"))) {
                        Label("Chia sẻ / Lưu file về máy", systemImage: "square.and.arrow.up")
                            .foregroundStyle(store.accentColor)
                    }
                    Text("File JSON chứa toàn bộ danh mục, thư mục con, sản phẩm và giá. KEY/ACC đã bán → mục \"Sao lưu KEY/ACC\".")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }

            Section("Hướng dẫn") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bấm 'Tạo file JSON backup' → app tải toàn bộ dữ liệu từ máy chủ", systemImage: "1.circle.fill")
                    Label("Bấm 'Lưu file về máy' → chọn vị trí lưu hoặc gửi lên Google Drive/iCloud", systemImage: "2.circle.fill")
                    Label("Khi chuyển server mới: dùng file để tham khảo và nhập lại cấu trúc", systemImage: "3.circle.fill")
                    Label("KEY/ACC đã bán xuất riêng ở mục 'Sao lưu KEY/ACC đã bán'", systemImage: "info.circle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }
        }
        .navigationTitle("Backup cửa hàng")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createBackup() async {
        loading = true; error = nil; backupURL = nil
        var out: [String: Any] = [
            "version": "1.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "appName": "KENIOS Store Backup"
        ]

        progress = "Đang tải cấu hình..."
        if let cfg = try? await store.api.storeConfig() {
            out["config"] = [
                "logoName": cfg.logoName, "logoUrl": cfg.logoUrl,
                "bannerType": cfg.bannerType, "bannerUrl": cfg.bannerUrl
            ]
        }

        progress = "Đang tải danh mục..."
        let cats = (try? await store.api.storeCategories()) ?? []
        var catsArr: [[String: Any]] = []

        for (i, cat) in cats.enumerated() {
            progress = "Danh mục \(i+1)/\(cats.count): \(cat.name)"
            var catObj: [String: Any] = [
                "id": cat.id, "name": cat.name,
                "media": cat.media.map { ["type": $0.type, "url": $0.url] }
            ]
            let folders = (try? await store.api.storeFolders(categoryId: cat.id)) ?? []
            var foldersArr: [[String: Any]] = []
            for folder in folders {
                var fObj: [String: Any] = [
                    "id": folder.id, "name": folder.name,
                    "media": folder.media.map { ["type": $0.type, "url": $0.url] }
                ]
                let products = (try? await store.api.storeProducts(folderId: folder.id)) ?? []
                fObj["products"] = products.map { p -> [String: Any] in [
                    "id": p.id, "name": p.name, "description": p.description,
                    "media": p.media.map { ["type": $0.type, "url": $0.url] },
                    "prices": p.prices.map { ["label": $0.label, "amount": $0.amount] },
                    "availableKeys": p.availableKeys, "isAcc": p.isAcc
                ]}
                foldersArr.append(fObj)
            }
            catObj["folders"] = foldersArr
            catsArr.append(catObj)
        }
        out["categories"] = catsArr

        progress = "Đang tạo file..."
        do {
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd_HHmmss"
            let name = "kenios_backup_\(fmt.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url)
            backupURL = url
            progress = "Xong! \(cats.count) danh mục · \(catsArr.flatMap { ($0["folders"] as? [[String: Any]]) ?? [] }.count) thư mục"
        } catch {
            self.error = error.localizedDescription; progress = ""
        }
        loading = false
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
                            title: "Điều chỉnh ví",
                            subtitle: "Nạp hoặc trừ tiền ví khách hàng thủ công")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section("Khách hàng") {
                TextField("Username hoặc ID khách hàng", text: $userIdentifier)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .onAppear { if userIdentifier.isEmpty && !prefillUser.isEmpty { userIdentifier = prefillUser } }

            Section("Loại thao tác") {
                Picker("", selection: $isDeduct) {
                    Text("Nạp tiền (+)").tag(false)
                    Text("Trừ tiền (-)").tag(true)
                }.pickerStyle(.segmented)
            }

            Section(isDeduct ? "Số tiền trừ" : "Số tiền nạp") {
                HStack {
                    TextField("Nhập số tiền (VND)", text: $amountText).keyboardType(.numberPad)
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

            Section("Ghi chú") {
                TextField("Lý do (tuỳ chọn)", text: $note, axis: .vertical).lineLimit(1...3)
            }

            Section {
                Button {
                    Task { await adjust() }
                } label: {
                    HStack {
                        if processing { ProgressView().tint(.white) }
                        Text(processing ? "Đang xử lý..." : (isDeduct ? "Trừ ví" : "Nạp ví"))
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
                Section("Lịch sử thao tác (phiên này)") {
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
        .navigationTitle("Điều chỉnh ví")
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
                HStack { Spacer(); ProgressView("Đang tải..."); Spacer() }
            } else if let s = stats {
                Section("Doanh thu cửa hàng") {
                    HStack(spacing: 10) {
                        analyticsCard("Tổng cộng", kFormatVND(storeRevenue), .green)
                        analyticsCard("Đơn hoàn tất", "\(completedOrderCount)", .blue)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section("Người dùng") {
                    HStack(spacing: 10) {
                        analyticsCard("Tổng users", "\(s.totalUsers)", .purple)
                        analyticsCard("7 ngày mới", "+\(s.newUsers7d)", .orange)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section("AI & Hội thoại") {
                    HStack(spacing: 10) {
                        analyticsCard("Hội thoại", "\(s.totalConversations)", .teal)
                        analyticsCard("Tin nhắn", "\(s.totalMessages)", Theme.accent)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    HStack(spacing: 10) {
                        analyticsCard("Doanh thu AI", kFormatVND(s.revenueTotal), .green)
                        analyticsCard("30 ngày", kFormatVND(s.revenue30d), .mint)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if !topProducts.isEmpty {
                    Section("Top sản phẩm bán chạy") {
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
                                    Text("\(item.count) đơn").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !s.topProviders.isEmpty {
                    Section("AI provider phổ biến") {
                        let maxCount = s.topProviders.first?.count ?? 1
                        ForEach(s.topProviders, id: \.provider) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(p.provider).font(.subheadline)
                                    Spacer()
                                    Text("\(p.count) lượt").font(.caption2).foregroundStyle(.secondary)
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
                Text("Không tải được thống kê.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Thống kê & Phân tích")
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

// ======================== Khôi phục backup JSON ========================
struct StoreRestoreBackupView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImporter = false
    @State private var parsedCategories: [[String: Any]] = []
    @State private var catCount = 0
    @State private var folderCount = 0
    @State private var productCount = 0
    @State private var loading = false
    @State private var progress = ""
    @State private var message: String?
    @State private var isError = false
    @State private var restored = false

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "arrow.up.doc.fill",
                            title: "Khôi phục backup",
                            subtitle: "Nhập file JSON backup để tạo lại cấu trúc cửa hàng")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section("Chọn file backup") {
                Button { showImporter = true } label: {
                    Label("Chọn file JSON backup", systemImage: "doc.badge.plus")
                }
                if !parsedCategories.isEmpty {
                    Label("\(catCount) danh mục · \(folderCount) thư mục · \(productCount) sản phẩm",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            if !parsedCategories.isEmpty && !restored {
                Section("Thực hiện") {
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack {
                            if loading { ProgressView().padding(.trailing, 4) }
                            Label(loading ? "Đang khôi phục..." : "Bắt đầu khôi phục",
                                  systemImage: "arrow.counterclockwise")
                        }
                    }
                    .disabled(loading)
                    if !progress.isEmpty {
                        Text(progress).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(isError ? .red : .green).font(.footnote) }
            }

            Section("Lưu ý") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Chỉ tạo mới — không ghi đè cấu trúc đã có", systemImage: "info.circle")
                    Label("KEY/ACC cũ KHÔNG được khôi phục từ file này", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Label("Nên xoá cửa hàng cũ trước khi khôi phục (nếu muốn sạch)", systemImage: "trash.circle")
                        .foregroundStyle(.red)
                }
                .font(.caption)
            }
        }
        .navigationTitle("Khôi phục backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json, .text, .plainText, .data, .item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await parseFile(url) }
            }
        }
    }

    private func parseFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = json["categories"] as? [[String: Any]] else {
            isError = true; message = "File không hợp lệ hoặc sai định dạng."; return
        }
        parsedCategories = cats
        catCount = cats.count
        let folders = cats.flatMap { ($0["folders"] as? [[String: Any]]) ?? [] }
        folderCount = folders.count
        productCount = folders.flatMap { ($0["products"] as? [[String: Any]]) ?? [] }.count
        message = nil; isError = false; restored = false
    }

    private func restore() async {
        loading = true; isError = false; message = nil
        var doneCount = 0
        for cat in parsedCategories {
            guard let name = cat["name"] as? String, !name.isEmpty else { continue }
            let media = (cat["media"] as? [[String: String]]) ?? []
            progress = "Danh mục: \(name)"
            guard let catRes = try? await store.api.adminStoreSaveCategory(id: nil, name: name, media: media),
                  let catId = catRes.id, catId > 0 else { continue }
            doneCount += 1
            for folder in (cat["folders"] as? [[String: Any]]) ?? [] {
                guard let fName = folder["name"] as? String, !fName.isEmpty else { continue }
                let fMedia = (folder["media"] as? [[String: String]]) ?? []
                progress = "  Thư mục: \(fName)"
                guard let fRes = try? await store.api.adminStoreSaveFolder(id: nil, categoryId: catId,
                                                                            name: fName, media: fMedia),
                      let fId = fRes.id, fId > 0 else { continue }
                for product in (folder["products"] as? [[String: Any]]) ?? [] {
                    guard let pName = product["name"] as? String, !pName.isEmpty else { continue }
                    let pDesc = (product["description"] as? String) ?? ""
                    let pMedia = (product["media"] as? [[String: String]]) ?? []
                    let kind = (product["isAcc"] as? Bool) == true ? "acc" : "app"
                    progress = "    Sản phẩm: \(pName)"
                    guard let pRes = try? await store.api.adminStoreSaveProduct(
                        id: nil, folderId: fId, name: pName, description: pDesc,
                        media: pMedia, downloadUrl: "", downloadFileId: nil, kind: kind),
                          let pId = pRes.id, pId > 0 else { continue }
                    if let prices = product["prices"] as? [[String: Any]], !prices.isEmpty {
                        _ = try? await store.api.adminStoreSetPrices(productId: pId, prices: prices)
                    }
                }
            }
        }
        progress = ""
        isError = false
        message = "Khôi phục xong! Đã tạo \(doneCount)/\(catCount) danh mục."
        loading = false; restored = true
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
                            Label("\(promo.usedCount)\(promo.maxUses > 0 ? "/\(promo.maxUses)" : "") lượt",
                                  systemImage: "person.2")
                            if promo.minAmount > 0 {
                                Label("Tối thiểu \(kFormatVND(promo.minAmount))", systemImage: "cart")
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
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Danh sách mã (\(codes.count))")
                    Spacer()
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Mã khuyến mãi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Mã giảm giá") {
                    TextField("Tên mã (VD: SALE50)", text: $newCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Loại giảm", selection: $discountType) {
                        Text("Phần trăm (%)").tag("percent")
                        Text("Số tiền cố định (đ)").tag("fixed")
                    }
                    TextField(discountType == "percent" ? "Giảm bao nhiêu % (VD: 20)" : "Giảm bao nhiêu đ (VD: 10000)",
                              text: $discountValue)
                        .keyboardType(.numberPad)
                }
                Section("Điều kiện") {
                    TextField("Đơn tối thiểu (VD: 50000, để trống = không giới hạn)", text: $minAmount)
                        .keyboardType(.numberPad)
                    TextField("Số lần dùng tối đa (để trống = không giới hạn)", text: $maxUses)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Tạo mã mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Huỷ") { showAdd = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tạo") { Task { await createCode() } }
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
                Section("Thiết bị đã đăng ký") {
                    Label("\(stats.totalDevices) thiết bị", systemImage: "iphone")
                    Label("\(stats.totalUsers) người dùng", systemImage: "person.2")
                }
            }

            Section("Nội dung thông báo") {
                TextField("Tiêu đề", text: $notifTitle)
                TextField("Nội dung", text: $notifBody, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    Task { await sendNotif() }
                } label: {
                    HStack {
                        if sending { ProgressView().padding(.trailing, 4) }
                        Text(sending ? "Đang gửi..." : "Gửi cho tất cả người dùng")
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

            Section("Hướng dẫn cấu hình APNs") {
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
        .navigationTitle("Gửi thông báo")
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
