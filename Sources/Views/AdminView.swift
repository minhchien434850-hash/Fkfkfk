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

    var body: some View {
        NavigationStack {
            List {
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
                                        Button("Free") { Task { await setPlan(u, "free") } }
                                        Button("Pro") { Task { await setPlan(u, "pro") } }
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

    private func loadPendingPayments() async {
        // Filter payment history for pending items
        let allHistory = (try? await store.api.paymentHistory()) ?? []
        pendingPayments = allHistory.filter { $0.status == "pending" }
    }

    private func ban(_ u: AdminUser, _ banned: Bool) async {
        do { _ = try await store.api.adminBan(u.id, banned: banned); await reload() }
        catch { self.error = error.localizedDescription }
    }

    private func setPlan(_ u: AdminUser, _ plan: String) async {
        do { _ = try await store.api.adminSetPlan(u.id, plan: plan); await reload() }
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
