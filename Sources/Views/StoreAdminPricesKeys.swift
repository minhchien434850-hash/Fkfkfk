import SwiftUI
import UniformTypeIdentifiers
import PhotosUI


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
