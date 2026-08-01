import SwiftUI


// ======================== Admin Key Entry ========================
struct AdminKeyEntryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let provider: Provider
    var onDone: () -> Void
    @State private var key = ""
    @State private var message: String?
    @State private var isError = false
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle().fill(providerColor(provider.id)).frame(width: 10, height: 10)
                        Text(provider.label).bold()
                    }
                    SecureField("Dán API key hệ thống tại đây", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Key này sẽ được dùng làm fallback cho tất cả người dùng chưa có key riêng.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if checking { ProgressView().padding(.trailing, 4) }
                            Text(checking ? "Đang lưu..." : "Lưu key hệ thống")
                        }
                    }
                    .disabled(key.isEmpty || checking)
                    Button("Xóa key", role: .destructive) {
                        Task { await remove() }
                    }
                }
                if let message {
                    Text(message).font(.footnote)
                        .foregroundStyle(isError ? .red : .green)
                }
            }
            .navigationTitle("API Key Hệ Thống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } }
            }
        }
    }

    private func save() async {
        checking = true; message = nil
        do {
            let r = try await store.api.adminSaveKey(provider: provider.id, apiKey: key)
            isError = false; message = r.message
            onDone()
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            isError = true; message = error.localizedDescription
        }
        checking = false
    }

    private func remove() async {
        do {
            _ = try await store.api.adminDeleteKey(provider: provider.id)
            onDone(); dismiss()
        } catch { message = error.localizedDescription; isError = true }
    }
}

// ======================== Đổi mật khẩu (admin) ========================
struct AdminPasswordSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let user: AdminUser
    var onDone: () -> Void
    @State private var newPassword = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Đổi mật khẩu cho", "Reset password for") + " \(user.username)") {
                    SecureField(store.t("Mật khẩu mới (≥6 ký tự)", "New password (≥6 chars)"), text: $newPassword)
                    Button(store.t("Xác nhận", "Confirm")) { Task { await save() } }.disabled(newPassword.count < 6)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(store.t("Đổi mật khẩu", "Change password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
        }
    }
    private func save() async {
        do {
            _ = try await store.api.adminSetPassword(user.id, newPassword: newPassword)
            onDone(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// ======================== Cài đặt ngân hàng (admin) ========================
struct BankSettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var s = BankSettings(bankCode: "970416", bankShort: "ACB",
                                        bankAccount: "23252921", bankName: "TRAN MINH CHIEN",
                                        bankWebhook: "", bankApikey: "", acbApiToken: "")
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ngân hàng nhận tiền (hiện QR cho khách khi nạp)") {
                    TextField("Mã ngân hàng VietQR (vd ACB = 970416)", text: $s.bankCode)
                        .keyboardType(.numberPad)
                    TextField("Tên ngân hàng ngắn (vd ACB)", text: $s.bankShort)
                        .textInputAutocapitalization(.characters)
                    TextField("Số tài khoản", text: $s.bankAccount).keyboardType(.numberPad)
                    TextField("Chủ tài khoản (IN HOA, không dấu)", text: $s.bankName)
                        .textInputAutocapitalization(.characters)
                    TextField("Webhook (tuỳ chọn)", text: $s.bankWebhook)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Nạp tiền tự động — ACB (thueapibank.vn)") {
                    TextField("API token ACB (thueapibank.vn)", text: $s.acbApiToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Dán API token ACB từ thueapibank.vn. Hệ thống tự đọc lịch sử giao dịch mỗi ~20 giây, khớp nội dung 'KENIOS <mã>' + số tiền để tự cộng PRO / cấp key sản phẩm. Để trống thì admin xác nhận tay.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Tự động xác nhận giao dịch (tuỳ chọn khác)") {
                    TextField("API key giao dịch (Casso / Sepay...)", text: $s.bankApikey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Dùng webhook của Casso/Sepay nếu muốn. Để trống nếu đã dùng token ACB ở trên.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Lưu") { Task { await save() } } }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
                }
                Section {
                    Text("Mã VietQR (Napas): ACB 970416 · Vietcombank 970436 · Techcombank 970407 · MB 970422 · BIDV 970418 · VPBank 970432.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Thông tin ngân hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        if let r = try? await store.api.adminGetBank() { s = r }
    }
    private func save() async {
        message = nil
        do { let r = try await store.api.adminSetBank(s); isError = false; message = r.message }
        catch { isError = true; message = error.localizedDescription }
    }
}

// ======================== Giá gói nâng cấp PRO (admin) ========================
struct ProPriceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var packages: [PaymentPackage] = []
    @State private var prices: [String: String] = [:]   // id -> text giá
    @State private var message: String?
    @State private var isError = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Giá 3 gói PRO (VND)") {
                    if packages.isEmpty {
                        Text("Đang tải...").foregroundStyle(.secondary)
                    }
                    ForEach(packages) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name ?? p.id).font(.subheadline.bold())
                            HStack {
                                TextField("Giá VND", text: Binding(
                                    get: { prices[p.id] ?? "\(p.amount)" },
                                    set: { prices[p.id] = $0.filter { $0.isNumber } }))
                                    .keyboardType(.numberPad)
                                Text("đ").foregroundStyle(.secondary)
                            }
                            if let d = p.days { Text("Thời hạn \(d) ngày").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    Button {
                        Task { await saveAll() }
                    } label: {
                        HStack {
                            if loading { ProgressView().padding(.trailing, 4) }
                            Text(loading ? "Đang lưu..." : "Lưu tất cả giá")
                        }
                    }
                    .disabled(loading || packages.isEmpty)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
                }
                Section {
                    Text("3 gói PRO theo thời hạn: tháng / 6 tháng / 1 năm. Khách bấm vào gói nào sẽ hiện QR chuyển khoản đúng số tiền đó; xác nhận xong tài khoản lên PRO tới ngày hết hạn. Không dùng credits.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Giá gói PRO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        if let r = try? await store.api.adminGetPro(), let pkgs = r.packages {
            packages = pkgs
            for p in pkgs { prices[p.id] = "\(p.amount)" }
        }
    }

    private func saveAll() async {
        loading = true; message = nil
        do {
            for p in packages {
                if let txt = prices[p.id], let v = Int(txt.filter { $0.isNumber }) {
                    let r = try await store.api.adminSetPro(package: p.id, price: v)
                    if let pkgs = r.packages { packages = pkgs }
                }
            }
            isError = false; message = "Đã lưu giá 3 gói."
        } catch {
            isError = true; message = error.localizedDescription
        }
        loading = false
    }
}

// ======================== Log lỗi hệ thống (admin) ========================
struct ErrorLogView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var logs: [ErrorLog] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if logs.isEmpty {
                    Text("Chưa có lỗi nào được ghi.").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.context ?? "-").font(.caption.bold())
                            Text(e.detail ?? "").font(.caption2).foregroundStyle(.red)
                            HStack {
                                if let u = e.username { Text(u).font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                                Text(timeText(e.createdAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Log lỗi hệ thống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Xóa hết", role: .destructive) { Task { await clear() } }
                        .disabled(logs.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .alert("Lỗi", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func reload() async {
        do { logs = try await store.api.adminErrors() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func clear() async {
        do { _ = try await store.api.adminClearErrors(); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func timeText(_ ts: Int?) -> String {
        guard let ts else { return "" }
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
