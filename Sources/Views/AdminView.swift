import SwiftUI

struct AdminView: View {
    @EnvironmentObject var store: AppStore
    @State private var users: [AdminUser] = []
    @State private var error: String?
    @State private var message: String?
    @State private var pwUser: AdminUser?
    @State private var walletUser: AdminUser?
    @State private var paymentId = ""
    @State private var showBank = false
    @State private var showErrors = false
    @State private var stats: AdminStats?
    @State private var statsError: String?
    @State private var showPro = false
    @State private var pendingPayments: [PaymentRecord] = []
    @State private var maintMsg = "Ứng dụng đang nâng cấp phiên bản. Vui lòng đợi trong giây lát."
    // §9.1 — cảnh báo xâm nhập
    @State private var secEnabled = false
    @State private var secToken = ""
    @State private var secChat = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KHeroHeader(icon: "crown.fill",
                                title: store.t("Quản trị", "Admin"),
                                subtitle: store.t("Thống kê · người dùng · đơn hàng · hệ thống",
                                                  "Stats · users · orders · system"),
                                useLogo: true)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                // ==================== 📊 Thống kê ====================
                Section {
                    if let stats {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            statCard(icon: "person.2.fill", value: "\(stats.totalUsers)", label: "Tổng người dùng", color: .blue)
                            statCard(icon: "person.badge.plus", value: "\(stats.newUsers7d)", label: "Mới 7 ngày", color: .green)
                            statCard(icon: "bubble.left.and.bubble.right.fill", value: "\(stats.totalConversations)", label: "Hội thoại", color: .orange)
                            statCard(icon: "text.bubble.fill", value: "\(stats.totalMessages)", label: "Tin nhắn", color: Theme.purple)
                            statCard(icon: "banknote.fill", value: formatRevenue(stats.revenue30d), label: "Doanh thu 30 ngày", color: .pink)
                            statCard(icon: "doc.fill", value: "\(stats.totalFiles)", label: "Tổng file", color: .teal)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    } else if let statsError {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(store.t("Không tải được thống kê", "Could not load stats"), systemImage: "exclamationmark.triangle")
                                .font(.subheadline.bold()).foregroundStyle(.orange)
                            Text(statsError).font(.caption2).foregroundStyle(.secondary)
                            Button(store.t("Thử lại", "Retry")) { Task { await loadStats() } }
                                .font(.caption)
                        }
                    } else {
                        HStack { Spacer(); ProgressView(store.t("Đang tải thống kê...", "Loading stats...")); Spacer() }
                    }
                } header: {
                    Text("📊 " + store.t("Thống kê", "Statistics"))
                }

                // ==================== Hệ thống ====================
                Section(store.t("Hệ thống", "System")) {
                    Button { showBank = true } label: {
                        Label(store.t("Thông tin ngân hàng / nạp tiền", "Bank info / top-up"), systemImage: "banknote")
                    }
                    Button { showPro = true } label: {
                        Label(store.t("Giá gói nâng cấp PRO (VND)", "PRO upgrade price (VND)"), systemImage: "crown.fill")
                    }
                    Button { showErrors = true } label: {
                        Label(store.t("Log lỗi hệ thống", "System error log"), systemImage: "exclamationmark.triangle")
                    }
                }

                // ==================== Thanh toán chờ duyệt ====================
                Section(store.t("Thanh toán chờ duyệt", "Payments awaiting approval")) {
                    if pendingPayments.isEmpty {
                        Text(store.t("Không có thanh toán nào chờ duyệt.", "No payments awaiting approval."))
                            .foregroundStyle(.secondary).font(.footnote)
                    } else {
                        ForEach(pendingPayments) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.t("Đơn", "Order") + " #\(payment.id)")
                                        .font(.subheadline.bold())
                                    Text(payment.credits > 0
                                         ? "\(payment.amount)đ → \(payment.credits) credits"
                                         : "\(payment.amount)đ → " + store.t("Nâng cấp PRO", "PRO upgrade"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let ref = payment.ref, !ref.isEmpty {
                                        Text(ref).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task { await confirmPaymentById(payment.id) }
                                } label: {
                                    Text(store.t("Xác nhận", "Confirm"))
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                // ==================== Xác nhận thanh toán thủ công ====================
                Section(store.t("Xác nhận bằng ID", "Confirm by ID")) {
                    HStack {
                        TextField(store.t("ID đơn thanh toán", "Payment order ID"), text: $paymentId)
                            .keyboardType(.numberPad)
                        Button(store.t("Xác nhận", "Confirm")) { Task { await confirmPayment() } }
                            .disabled(paymentId.isEmpty)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.green) }
                }

                // ==================== Chế độ bảo trì ====================
                Section(store.t("Chế độ bảo trì", "Maintenance mode")) {
                    Toggle(store.t("Bật bảo trì (khoá app người dùng)", "Enable maintenance (lock users out)"), isOn: Binding(
                        get: { store.maintenance },
                        set: { on in Task { await setMaintenance(on) } }))
                    TextField(store.t("Thông báo bảo trì", "Maintenance message"), text: $maintMsg, axis: .vertical)
                        .lineLimit(1...3)
                    Text(store.t("Khi bật, mọi người dùng (trừ admin) thấy màn hình khoá tới khi bạn tắt.",
                                 "When on, all users (except admins) see a lock screen until you turn it off."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // "Giọng chào toàn cục" đã GỘP vào Cài đặt → Lời chào khi mở app (chỉ admin thấy).

                // ============ Thông báo & Lời chào (chuyển từ Cửa hàng sang) ============
                Section {
                    NavigationLink {
                        AppNoticesEditor()
                    } label: {
                        Label(store.t("Thông báo & Lời chào", "Notices & Welcome"),
                              systemImage: "bell.badge.fill")
                    }
                } footer: {
                    Text(store.t("Thông báo cập nhật phiên bản mới + Lời chào toàn cục (popup) cho MỌI người dùng. (Cài đặt của app — không phải cửa hàng.)",
                                 "New-version update notice + global welcome popup for ALL users. (App setting — not the store.)"))
                        .font(.caption2)
                }

                // ("Duyệt rút tiền người bán" đã gỡ theo yêu cầu — cùng với cửa hàng người bán.)

                // §9.1 — Cảnh báo xâm nhập qua Telegram
                Section {
                    Toggle(store.t("Bật cảnh báo xâm nhập", "Enable intrusion alerts"), isOn: $secEnabled)
                    SecureField(store.t("Bot Token Telegram", "Telegram Bot Token"), text: $secToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(store.t("Chat ID nhận cảnh báo", "Alert chat_id"), text: $secChat)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button(store.t("Lưu", "Save")) { Task { await saveSecurityAlert(test: false) } }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                        Button(store.t("Gửi thử", "Send test")) { Task { await saveSecurityAlert(test: true) } }
                            .buttonStyle(.bordered)
                    }
                } header: {
                    Text(store.t("Bảo mật — Cảnh báo xâm nhập", "Security — Intrusion alerts"))
                } footer: {
                    Text(store.t("Khi phát hiện dò quét/spam (vượt rate-limit), hệ thống gửi cảnh báo tới Telegram của bạn. Tạo bot ở @BotFather để lấy Token & chat_id.",
                                 "On scan/spam (rate-limit breach), the server alerts your Telegram. Create a bot via @BotFather for the Token & chat_id."))
                        .font(.caption2)
                }

                // ==================== Danh sách người dùng ====================
                Section(store.t("Người dùng", "Users") + " (\(users.count))") {
                    ForEach(users) { u in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(u.username).bold()
                                if u.isAdmin == true {
                                    Text("admin").font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.2))
                                        .foregroundStyle(Theme.accent)
                                        .clipShape(Capsule())
                                }
                                PlanBadge(plan: u.isAdmin == true ? "pro" : (u.plan ?? "free"))
                                Spacer()
                                if (u.banned ?? 0) == 1 {
                                    Text("đã khóa").font(.caption).foregroundStyle(.red)
                                } else if (u.status ?? "active") == "suspended" {
                                    Text("tạm ngưng").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            if let pid = u.publicId, !pid.isEmpty {
                                Text("ID: \(pid)").font(.caption2).foregroundStyle(Theme.accent)
                            }
                            if let e = u.email, !e.isEmpty {
                                Text(e).font(.caption).foregroundStyle(.secondary)
                            }
                            if let p = u.phone, !p.isEmpty {
                                Text(p).font(.caption).foregroundStyle(.secondary)
                            }
                            if let lf = u.lastFeature, !lf.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.caption2).foregroundStyle(.green)
                                    Text(store.t("Đang dùng:", "Using:") + " \(lf)").font(.caption2).foregroundStyle(.green)
                                    if let ls = u.lastSeen, ls > 0 {
                                        Text("· " + seenAgo(ls)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            HStack {
                                Menu(store.t("Thao tác", "Actions")) {
                                    Button((u.banned ?? 0) == 1 ? store.t("Mở khóa", "Unban") : store.t("Khóa tài khoản", "Ban account"),
                                           role: (u.banned ?? 0) == 1 ? nil : .destructive) {
                                        Task { await ban(u, !((u.banned ?? 0) == 1)) }
                                    }
                                    Menu(store.t("Đặt gói", "Set plan")) {
                                        Button(store.t("PRO · nửa tháng", "PRO · half month")) { Task { await setPlan(u, "pro", 15) } }
                                        Button(store.t("PRO · 1 tháng", "PRO · 1 month")) { Task { await setPlan(u, "pro", 30) } }
                                        Button(store.t("PRO · 1 năm", "PRO · 1 year")) { Task { await setPlan(u, "pro", 365) } }
                                        Button(store.t("PRO · vĩnh viễn", "PRO · lifetime")) { Task { await setPlan(u, "pro", 0) } }
                                        Button("Free", role: .destructive) { Task { await setPlan(u, "free", nil) } }
                                    }
                                    if (u.status ?? "active") == "suspended" {
                                        Button(store.t("Mở lại hoạt động", "Re-activate")) { Task { await unsuspend(u) } }
                                    } else {
                                        Menu(store.t("Tạm ngưng", "Suspend")) {
                                            Button(store.t("15 phút", "15 minutes")) { Task { await suspend(u, 15) } }
                                            Button(store.t("1 giờ", "1 hour")) { Task { await suspend(u, 60) } }
                                            Button(store.t("1 ngày", "1 day")) { Task { await suspend(u, 1440) } }
                                            Button(store.t("Vô thời hạn", "Indefinitely")) { Task { await suspend(u, 0) } }
                                        }
                                    }
                                    Button(store.t("Đổi mật khẩu giúp", "Reset password")) { pwUser = u }
                                    Button(store.t("Cộng / Trừ tiền ví", "Adjust wallet")) { walletUser = u }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(store.t("Quản trị", "Admin"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThreeDLogoText(size: 20)
                }
            }
            .task {
                await reload()
                await loadStats()
                await loadPendingPayments()
                await loadSecurityAlert()
                // Tự làm mới danh sách người dùng mỗi 15s để xem "đang dùng" theo thời gian thực
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await reload()
                }
            }
            .refreshable {
                await reload()
                await loadStats()
                await loadPendingPayments()
            }
            .sheet(item: $pwUser) { u in AdminPasswordSheet(user: u) { Task { await reload() } } }
            .sheet(item: $walletUser) { u in
                NavigationStack { AdminWalletAdjustView(prefillUser: u.publicId ?? u.username) }
            }
            .sheet(isPresented: $showBank) { BankSettingsSheet() }
            .sheet(isPresented: $showErrors) { ErrorLogView() }
            .sheet(isPresented: $showPro) { ProPriceSheet() }
            .alert("Lỗi", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    // Thời gian hoạt động gần nhất (tương đối)
    private func seenAgo(_ ts: Int) -> String {
        let s = max(0, Int(Date().timeIntervalSince1970) - ts)
        if s < 60 { return store.t("vừa xong", "just now") }
        if s < 3600 { return "\(s/60) " + store.t("phút trước", "min ago") }
        if s < 86400 { return "\(s/3600) " + store.t("giờ trước", "h ago") }
        return "\(s/86400) " + store.t("ngày trước", "d ago")
    }

    // MARK: - Stat Card

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatRevenue(_ amount: Int) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM", Double(amount) / 1_000_000)
        } else if amount >= 1_000 {
            return String(format: "%.0fK", Double(amount) / 1_000)
        }
        return "\(amount)"
    }

    // MARK: - Actions

    private func confirmPayment() async {
        guard let pid = Int(paymentId) else { return }
        message = nil; error = nil
        do {
            let r = try await store.api.adminConfirmPayment(pid)
            message = r.message; paymentId = ""
            await reload()
            await loadPendingPayments()
        } catch { self.error = error.localizedDescription }
    }

    private func confirmPaymentById(_ pid: Int) async {
        message = nil; error = nil
        do {
            let r = try await store.api.adminConfirmPayment(pid)
            message = r.message
            await reload()
            await loadPendingPayments()
        } catch { self.error = error.localizedDescription }
    }

    private func reload() async {
        do { users = try await store.api.adminUsers() }
        catch { self.error = error.localizedDescription }
    }

    private func loadStats() async {
        statsError = nil
        do {
            stats = try await store.api.adminStats()
        } catch {
            stats = nil
            statsError = error.localizedDescription
        }
    }

    // §9.1 — cảnh báo xâm nhập
    private func loadSecurityAlert() async {
        if let c = try? await store.api.getSecurityAlert() {
            secEnabled = c.enabled ?? false
            secToken = c.botToken ?? ""
            secChat = c.chatId ?? ""
        }
    }

    private func saveSecurityAlert(test: Bool) async {
        do {
            try await store.api.setSecurityAlert(enabled: secEnabled,
                                                 botToken: secToken, chatId: secChat, test: test)
            message = test
                ? store.t("Đã gửi tin thử — kiểm tra Telegram.", "Test sent — check Telegram.")
                : store.t("Đã lưu cảnh báo bảo mật.", "Security alert saved.")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPendingPayments() async {
        // Filter payment history for pending items
        let allHistory = (try? await store.api.paymentHistory()) ?? []
        pendingPayments = allHistory.filter { $0.status == "pending" }
    }

    private func ban(_ u: AdminUser, _ banned: Bool) async {
        do { _ = try await store.api.adminBan(u.id, banned: banned); await reload() }
        catch { self.error = error.localizedDescription }
    }

    private func setPlan(_ u: AdminUser, _ plan: String, _ days: Int?) async {
        do { _ = try await store.api.adminSetPlan(u.id, plan: plan, days: days); await reload() }
        catch { self.error = error.localizedDescription }
    }

    private func suspend(_ u: AdminUser, _ minutes: Int) async {
        do { _ = try await store.api.adminSuspend(u.id, minutes: minutes); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func unsuspend(_ u: AdminUser) async {
        do { _ = try await store.api.adminUnsuspend(u.id); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func setMaintenance(_ on: Bool) async {
        do {
            _ = try await store.api.adminSetMaintenance(on: on, message: maintMsg)
            store.maintenance = on
        } catch { self.error = error.localizedDescription }
    }
}

// ============================ §7 Đợt 4 — Admin duyệt rút tiền người bán ============================
struct AdminWithdrawalsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [AdminWithdrawal] = []
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if items.isEmpty {
                Text(store.t("Chưa có yêu cầu rút tiền.", "No withdrawal requests."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(w.seller).font(.subheadline.bold())
                            Spacer()
                            Text(kFormatVND(w.amount)).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                        }
                        Text(w.bankInfo).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(statusLabel(w.status)).font(.caption.bold()).foregroundStyle(statusColor(w.status))
                            Spacer()
                            if w.status == "pending" {
                                Button(store.t("Đã chi", "Paid")) { Task { await act(w.id, "paid") } }
                                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(busy)
                                Button(store.t("Từ chối", "Reject")) { Task { await act(w.id, "reject") } }
                                    .buttonStyle(.bordered).controlSize(.small).tint(.red).disabled(busy)
                            }
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(store.t("Duyệt rút tiền", "Withdrawals"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "paid": return store.t("Đã chi", "Paid")
        case "rejected": return store.t("Từ chối", "Rejected")
        default: return store.t("Chờ duyệt", "Pending")
        }
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "paid": return .green; case "rejected": return .red; default: return .orange }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        items = (try? await store.api.adminUStoreWithdrawals()) ?? []
    }
    private func act(_ wid: Int, _ action: String) async {
        busy = true; defer { busy = false }
        try? await store.api.adminUStoreWithdrawAction(wid, action: action)
        await reload()
    }
}

// "Giọng chào toàn cục" (GlobalWelcomeEditor) đã được GỘP vào
// SettingsView → WelcomeGreetingView (mục "Lời chào khi mở app", chỉ admin thấy).

// ============ Thông báo cập nhật phiên bản + Lời chào toàn cục (Quản trị app) ============
struct AppNoticesEditor: View {
    @EnvironmentObject var store: AppStore
    // §1.2 — Thông báo cập nhật phiên bản
    @State private var latestVersion = ""
    @State private var updateUrl = ""
    @State private var updateMessage = ""
    // §1.3 — Lời chào toàn cục (popup)
    @State private var welcomePopupEnabled = false
    @State private var welcomePopupTitle = ""
    @State private var welcomePopupText = ""
    // Truyền lại các trường bắt buộc để không ghi đè rỗng
    @State private var logoName = ""
    @State private var logoUrl = ""
    @State private var bannerType = "image"
    @State private var bannerUrl = ""
    @State private var loaded = false
    @State private var loadError = false
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            if !loaded {
                Section {
                    if loadError {
                        Label(store.t("Không tải được cấu hình từ máy chủ.",
                                      "Couldn't load config from server."), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                        Button(store.t("Thử lại", "Retry")) { Task { await load() } }.font(.caption.bold())
                    } else {
                        HStack { ProgressView(); Text(store.t("Đang tải...", "Loading...")).font(.caption) }
                    }
                } footer: {
                    Text(store.t("Cần máy chủ bật (đã chạy capnhat-vps.sh). Chưa tải được thì chưa Lưu để tránh ghi đè cấu hình.",
                                 "Requires the server up (capnhat-vps.sh run). Until loaded, saving is disabled to avoid overwriting config."))
                        .font(.caption2)
                }
            }
            Section {
                TextField(store.t("Phiên bản mới nhất (vd 3.1)", "Latest version (e.g. 3.1)"), text: $latestVersion)
                    .keyboardType(.decimalPad)
                TextField(store.t("Link tải/cập nhật (https://...)", "Update link (https://...)"), text: $updateUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField(store.t("Lời nhắn cập nhật (tuỳ chọn)", "Update message (optional)"),
                          text: $updateMessage, axis: .vertical).lineLimit(1...3)
            } header: {
                Text(store.t("Thông báo cập nhật phiên bản", "Version update notice"))
            } footer: {
                Text(store.t("Khi bản mới > phiên bản đang cài, mọi user thấy popup 'Cập nhật ngay' mở link. Để trống Phiên bản để tắt.",
                             "When newer than the installed version, all users see an 'Update now' popup opening the link. Leave version empty to disable."))
                    .font(.caption2)
            }

            Section {
                Toggle(store.t("Bật lời chào toàn cục", "Enable global welcome popup"), isOn: $welcomePopupEnabled)
                if welcomePopupEnabled {
                    TextField(store.t("Tiêu đề (vd: Chào mừng!)", "Title (e.g. Welcome!)"), text: $welcomePopupTitle)
                    TextField(store.t("Nội dung lời chào cho mọi khách", "Welcome text for all users"),
                              text: $welcomePopupText, axis: .vertical).lineLimit(2...5)
                }
            } header: {
                Text(store.t("Lời chào toàn cục (popup)", "Global welcome popup"))
            } footer: {
                Text(store.t("Popup hiện 1 lần khi MỌI người dùng mở app (không chỉ admin).",
                             "Shown once when ANY user opens the app (not only admin)."))
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if saving { ProgressView().padding(.trailing, 4) }
                        Text(store.t("Lưu", "Save")).bold()
                    }
                }.disabled(saving || !loaded)
                if let message {
                    Text(message).font(.caption).foregroundStyle(isError ? .red : .green)
                }
            }
        }
        .navigationTitle(store.t("Thông báo & Lời chào", "Notices & Welcome"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loadError = false
        guard let c = try? await store.api.storeConfig() else { loadError = true; return }
        latestVersion = c.latestVersion ?? ""
        updateUrl = c.updateUrl ?? ""
        updateMessage = c.updateMessage ?? ""
        welcomePopupEnabled = c.welcomePopupEnabled ?? false
        welcomePopupTitle = c.welcomePopupTitle ?? ""
        welcomePopupText = c.welcomePopupText ?? ""
        logoName = c.logoName; logoUrl = c.logoUrl
        bannerType = c.bannerType; bannerUrl = c.bannerUrl
        loaded = true
    }

    private func save() async {
        guard loaded else { return }
        saving = true; message = nil
        defer { saving = false }
        do {
            let r = try await store.api.adminStoreSetConfig(
                logoName: logoName, logoUrl: logoUrl,
                bannerType: bannerType, bannerUrl: bannerUrl,
                welcomePopupEnabled: welcomePopupEnabled,
                welcomePopupTitle: welcomePopupTitle,
                welcomePopupText: welcomePopupText,
                latestVersion: latestVersion, updateUrl: updateUrl,
                updateMessage: updateMessage)
            isError = false; message = r.message
        } catch {
            isError = true; message = error.localizedDescription
        }
    }
}
