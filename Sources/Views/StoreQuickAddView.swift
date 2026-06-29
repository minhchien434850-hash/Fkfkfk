import SwiftUI
import UniformTypeIdentifiers
import PhotosUI


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
                // allowsMultipleSelection: true → iOS hiện ô TÍCH (✓) + nút "Mở" (Open); nhận MỌI loại file.
                DocumentPicker(allowsMultipleSelection: true) { urls in
                    if let url = urls.first { Task { await uploadFile(url) } }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { showDownloadPickerFor != nil },
                set: { if !$0 { showDownloadPickerFor = nil } }
            )) {
                if let pid = showDownloadPickerFor {
                    DocumentPicker(allowsMultipleSelection: true) { urls in
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
