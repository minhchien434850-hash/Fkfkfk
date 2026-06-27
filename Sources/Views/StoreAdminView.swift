import SwiftUI
import UniformTypeIdentifiers

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
            if media.count < 5 {
                Button { media.append(EditMedia()) } label: {
                    Label("Thêm ảnh / video", systemImage: "plus.circle")
                }
            }
            Button {
                showConverter = true
            } label: {
                Label("Chuyển đổi ảnh → link GIF / PNG / JPEG", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(store.accentColor)
            }
        } header: {
            Text("Ảnh / Video (dán link, tối đa 5)")
        } footer: {
            Text("Dán link từ bất kỳ dịch vụ nào: Imgur, Cloudinary, Giphy, v.v. Hoặc bấm \"Chuyển đổi\" để tạo link từ ảnh.")
                .font(.caption2)
        }
        .sheet(isPresented: $showConverter) {
            MediaConverterView().environmentObject(store)
        }
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
                        Label("Giao diện cửa hàng (logo, banner)", systemImage: "paintpalette")
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
            Section("Banner đầu trang") {
                Picker("Loại banner", selection: $bannerType) {
                    Text("Ảnh / GIF").tag("image")
                    Text("Video / MP4").tag("video")
                }.pickerStyle(.segmented)
                TextField("Dán link banner (GIF / PNG / JPEG / MP4...)", text: $bannerUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Hỗ trợ GIF động, PNG, JPEG, WEBP, MP4. Dùng Khám phá → Chuyển đổi để tạo link GIF/PNG từ ảnh bất kỳ.")
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
        }
    }
    private func save() async {
        message = nil
        do {
            let r = try await store.api.adminStoreSetConfig(logoName: logoName, logoUrl: logoUrl,
                                                            bannerType: bannerType, bannerUrl: bannerUrl)
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
                            StorePricesEditor(productId: pid, initial: product?.prices ?? [])
                        } label: { Label("Bảng giá theo thời hạn", systemImage: "tag") }
                        NavigationLink {
                            StoreKeysManager(productId: pid)
                        } label: { Label("Kho KEY sản phẩm", systemImage: "key") }
                    }
                } else {
                    Text("Lưu sản phẩm trước để thêm bảng giá & key.")
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
    @State private var rows: [EditPrice] = []
    @State private var message: String?
    @State private var isError = false

    private let presets = ["1 giờ", "1 ngày", "1 tuần", "1 tháng", "Vĩnh viễn"]

    var body: some View {
        Form {
            Section("Các mốc giá") {
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
            Section { Button("Lưu bảng giá") { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle("Bảng giá")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if rows.isEmpty {
                rows = initial.map { EditPrice(label: $0.label, amount: "\($0.amount)") }
                if rows.isEmpty { rows = [EditPrice()] }
            }
        }
    }

    private func save() async {
        message = nil
        let payload: [[String: Any]] = rows.compactMap { r in
            let label = r.label.trimmingCharacters(in: .whitespaces)
            let amount = Int(r.amount.filter { $0.isNumber }) ?? -1
            guard !label.isEmpty, amount >= 0 else { return nil }
            return ["label": label, "amount": amount]
        }
        do {
            let r = try await store.api.adminStoreSetPrices(productId: productId, prices: payload)
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Kho KEY ----
struct StoreKeysManager: View {
    @EnvironmentObject var store: AppStore
    let productId: Int
    @State private var info: StoreKeysInfo?
    @State private var newKeys = ""
    @State private var message: String?
    @State private var isError = false
    @State private var loading = false

    var body: some View {
        Form {
            Section("Thêm key (mỗi dòng 1 key)") {
                TextEditor(text: $newKeys).frame(minHeight: 120)
                Button("Thêm key") { Task { await addKeys() } }
                    .disabled(newKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let info {
                Section("Tồn kho: \(info.available) khả dụng / \(info.total) tổng") {
                    Button("Xoá tất cả key khả dụng", role: .destructive) {
                        Task { await deleteAvailable() }
                    }
                }
                Section("Danh sách key") {
                    if info.keys.isEmpty {
                        Text("Chưa có key nào.").foregroundStyle(.secondary)
                    } else {
                        ForEach(info.keys) { k in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.keyText).font(.caption.monospaced()).lineLimit(1)
                                    Text(k.status == "sold" ? "đã bán" : "khả dụng")
                                        .font(.caption2)
                                        .foregroundStyle(k.status == "sold" ? .orange : .green)
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
        .navigationTitle("Kho KEY")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        info = try? await store.api.adminStoreListKeys(productId: productId)
    }
    private func addKeys() async {
        message = nil
        do {
            let r = try await store.api.adminStoreAddKeys(productId: productId, text: newKeys)
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
