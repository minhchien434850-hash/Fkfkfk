import SwiftUI
import PhotosUI
import UIKit

// §7 — Đa người bán: "Cửa hàng của tôi" (tạo store · thêm sản phẩm · chia sẻ Store_ID)
// và "Tìm cửa hàng" theo Store_ID để xem shop người khác. Dữ liệu cô lập, RBAC ở backend.
struct MyStoreView: View {
    @EnvironmentObject var store: AppStore
    @State private var seg = 0

    // Cửa hàng của tôi
    @State private var myStore: MyStore?
    @State private var products: [MyStoreProduct] = []
    @State private var loading = false
    @State private var name = ""
    @State private var desc = ""
    @State private var saving = false
    @State private var message: String?

    @State private var showAddProduct = false

    // Tìm cửa hàng
    @State private var searchId = ""
    @State private var foundStore: MyStore?
    @State private var foundProducts: [MyStoreProduct] = []
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
            .sheet(isPresented: $showAddProduct) {
                AddMyProductView { await loadMine() }.environmentObject(store)
            }
        }
    }

    // MARK: - Cửa hàng của tôi
    @ViewBuilder private var myStorePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading { ProgressView().frame(maxWidth: .infinity) }

                // Thông tin store (tạo mới hoặc sửa)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("Thông tin cửa hàng", "Store info")).font(.subheadline.bold())
                    TextField(store.t("Tên cửa hàng", "Store name"), text: $name)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                    TextField(store.t("Mô tả (tuỳ chọn)", "Description (optional)"), text: $desc, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
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
                }
                .padding().kCard(16)

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

                    // Sản phẩm
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
                        ForEach(products) { p in productRow(p, canDelete: true) }
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.name).font(.title3.bold())
                        if let d = s.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                        Text("Store ID #\(s.id)").font(.caption2).foregroundStyle(Theme.accent)
                    }.padding().kCard(16)
                    Text(store.t("Sản phẩm (\(foundProducts.count))", "Products (\(foundProducts.count))")).font(.subheadline.bold())
                    ForEach(foundProducts) { p in productRow(p, canDelete: false) }
                }
            }
            .padding()
        }
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
                Text(kFormatVND(p.price)).font(.caption.bold()).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
            if canDelete {
                Button { Task { try? await store.api.deleteMyProduct(p.id); await loadMine() } } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
        }
        .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions
    private func loadMine() async {
        loading = true; defer { loading = false }
        if let r = try? await store.api.getMyStore() {
            myStore = r.store
            products = r.products ?? []
            if let s = r.store { name = s.name; desc = s.description ?? "" }
        }
    }

    private func saveStore() async {
        saving = true; defer { saving = false }
        message = nil
        do {
            let s = try await store.api.saveMyStore(
                name: name.trimmingCharacters(in: .whitespaces),
                description: desc, logoUrl: nil)
            myStore = s
            message = store.t("Đã lưu cửa hàng ✅", "Store saved ✅")
        } catch {
            message = error.localizedDescription
        }
    }

    private func findStore() async {
        guard let sid = Int(searchId) else { return }
        searching = true; defer { searching = false }
        searchError = nil; foundStore = nil; foundProducts = []
        do {
            let r = try await store.api.getUserStore(sid)
            foundStore = r.store
            foundProducts = r.products ?? []
        } catch {
            searchError = store.t("Không tìm thấy cửa hàng với ID này.", "No store found with this ID.")
        }
    }
}

// §7 — Sheet thêm/sửa sản phẩm cửa hàng cá nhân
struct AddMyProductView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onDone: () async -> Void

    @State private var name = ""
    @State private var priceText = ""
    @State private var desc = ""
    @State private var downloadUrl = ""
    @State private var imageItem: PhotosPickerItem?
    @State private var imageUrl = ""
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Thông tin sản phẩm", "Product info")) {
                    TextField(store.t("Tên sản phẩm", "Product name"), text: $name)
                    TextField(store.t("Giá (VND)", "Price (VND)"), text: $priceText).keyboardType(.numberPad)
                    TextField(store.t("Mô tả", "Description"), text: $desc, axis: .vertical).lineLimit(1...4)
                    TextField(store.t("Link tải/giao hàng (tuỳ chọn)", "Download/delivery link (optional)"), text: $downloadUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(store.t("Ảnh sản phẩm", "Product image")) {
                    if !imageUrl.isEmpty, let url = URL(string: imageUrl) {
                        CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { Color(.tertiarySystemBackground) }
                            .frame(height: 140).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    PhotosPicker(selection: $imageItem, matching: .images) {
                        Label(uploading ? store.t("Đang tải ảnh…", "Uploading…")
                                        : store.t("Chọn ảnh", "Choose image"),
                              systemImage: "photo").font(.subheadline)
                    }.disabled(uploading)
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
        if let url = try? await store.api.mediaUpload(
            dataBase64: data.base64EncodedString(), mime: "image/jpeg",
            name: "prod_\(Int(Date().timeIntervalSince1970)).jpg") {
            imageUrl = url
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        error = nil
        let media: [[String: String]] = imageUrl.isEmpty ? [] : [["type": "image", "url": imageUrl]]
        do {
            try await store.api.saveMyProduct(
                id: nil, name: name.trimmingCharacters(in: .whitespaces),
                description: desc, price: Int(priceText) ?? 0,
                media: media, downloadUrl: downloadUrl.isEmpty ? nil : downloadUrl)
            await onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
