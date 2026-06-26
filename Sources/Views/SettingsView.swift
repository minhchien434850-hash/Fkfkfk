import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var email = ""
    @State private var phone = ""
    @State private var newPassword = ""
    @State private var message: String?
    @State private var connected: Bool?
    @State private var showConnections = false
    @State private var showPayment = false
    @State private var cleanupDays = 30
    @State private var cleaning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "gearshape.fill",
                                title: "Cài đặt",
                                subtitle: "Tài khoản · giao diện · dọn dẹp · cache")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // SERVER — chỉ hiện khi CHƯA cài sẵn máy chủ mặc định (Config.defaultServerURL)
                if Config.defaultServerURL.isEmpty {
                    Section("Kết nối máy chủ (\(store.serverType))") {
                        LabeledContent("URL / IP", value: store.baseURL)
                        HStack {
                            Text("Trạng thái")
                            Spacer()
                            if let connected {
                                Circle().fill(connected ? .green : .red).frame(width: 8, height: 8)
                                Text(connected ? "Đang kết nối" : "Mất kết nối")
                                    .foregroundStyle(connected ? .green : .red)
                            } else { ProgressView() }
                        }
                        Button("Quản lý máy chủ (VPS / Hosting)") { showConnections = true }
                    }
                }

                // ACCOUNT
                Section("Tài khoản") {
                    LabeledContent("Tên đăng nhập", value: store.username ?? "-")
                    HStack {
                        Text("ID của bạn")
                        Spacer()
                        Text(store.publicId.isEmpty ? "—" : store.publicId)
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("Gói")
                        Spacer()
                        Text(store.isPro ? "PRO" : "Free")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                    }
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(store.credits)").foregroundStyle(Theme.accent)
                    }
                    Button("Nạp credits") { showPayment = true }
                    TextField("Gmail", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                    SecureField("Đổi mật khẩu (để trống nếu không đổi)", text: $newPassword)
                    Button("Lưu thay đổi") { Task { await saveProfile() } }
                }

                Section("Ngôn ngữ & Giao diện") {
                    Picker("Ngôn ngữ", selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) })) {
                        ForEach(kAppLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    Picker("Giao diện", selection: Binding(
                        get: { store.themeMode },
                        set: { store.setThemeMode($0) })) {
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                        Text("Tự động (cân bằng)").tag("system")
                    }
                }

                // ===== Màu chủ đạo =====
                Section("Màu chủ đạo của app") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(kAccentColors, id: \.name) { item in
                            Button {
                                store.setAccentColor(item.name)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 38, height: 38)
                                    if store.accentColorName == item.name {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // ===== Hiệu ứng logo =====
                Section("Hiệu ứng & Logo") {
                    Toggle("Logo có hiệu ứng động", isOn: Binding(
                        get: { store.logoAnimated },
                        set: { store.setLogoAnimated($0) }))
                    Text("Bật để logo KENIOS và logo cửa hàng có hiệu ứng chuyển động lấp lánh.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ===== Thông báo =====
                Section("Thông báo") {
                    Button {
                        store.requestNotificationPermission()
                        message = "Đã mở yêu cầu cấp quyền thông báo iOS."
                    } label: {
                        Label("Bật thông báo (sản phẩm mới, cập nhật)",
                              systemImage: "bell.badge")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Mở Cài đặt iOS để quản lý thông báo",
                              systemImage: "gear")
                    }
                    Text("Thông báo xuất hiện khi admin thêm sản phẩm mới hoặc có cập nhật bảo trì.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Dung lượng & Dọn dẹp") {
                    Picker("Xóa tin nhắn cũ hơn", selection: $cleanupDays) {
                        Text("7 ngày").tag(7)
                        Text("30 ngày").tag(30)
                        Text("90 ngày").tag(90)
                    }
                    .pickerStyle(.menu)

                    Button {
                        Task { await runCleanup() }
                    } label: {
                        HStack {
                            if cleaning {
                                ProgressView().tint(.red).padding(.trailing, 4)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Dọn dẹp cơ sở dữ liệu")
                        }
                        .foregroundStyle(.red)
                    }
                    .disabled(cleaning)
                }

                Section("Bộ nhớ đệm (Cache)") {
                    Button {
                        clearCache()
                    } label: { Label("Xoá cache của app", systemImage: "trash") }
                }

                if let message { Text(message).foregroundStyle(.green).font(.footnote) }

                Section {
                    Button("Đăng xuất", role: .destructive) { store.logout() }
                }
            }
            .navigationTitle("Cài đặt")
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .sheet(isPresented: $showPayment) { PaymentView() }
            .task {
                await store.refreshCredits()
                connected = (try? await store.api.getConfig()) != nil
            }
            .onAppear { email = store.email ?? ""; phone = store.phone ?? "" }
        }
    }

    private func clearCache() {
        // Xoá URLCache + thư mục Caches + tệp tạm
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for dir in [fm.urls(for: .cachesDirectory, in: .userDomainMask).first, fm.temporaryDirectory].compactMap({ $0 }) {
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for u in items { try? fm.removeItem(at: u) }
            }
        }
        message = "Đã xoá cache."
    }

    private func saveProfile() async {
        do {
            _ = try await store.api.updateProfile(email: email, phone: phone,
                                                   newPassword: newPassword.isEmpty ? nil : newPassword)
            store.updateLocalUser(email: email, phone: phone)
            newPassword = ""; message = "Đã cập nhật."
        } catch { message = error.localizedDescription }
    }

    private func runCleanup() async {
        cleaning = true
        message = nil
        do {
            let res = try await store.api.cleanupDatabase(days: cleanupDays)
            message = res.message
        } catch {
            message = "Lỗi: \(error.localizedDescription)"
        }
        cleaning = false
    }
}
