import SwiftUI
import UniformTypeIdentifiers
import PhotosUI


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
